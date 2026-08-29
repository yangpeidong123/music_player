import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_js/flutter_js.dart';
import 'package:dio/dio.dart';
import 'package:crypto/crypto.dart' as crypto_lib;
import 'package:encrypt/encrypt.dart' as encrypt_pkg;
import 'package:archive/archive.dart' as archive_pkg;

/// 洛雪音源元数据
@immutable
class SourceMeta {
  final String name;
  final String description;
  final String version;
  final String author;
  final String homepage;

  const SourceMeta({
    this.name = '',
    this.description = '',
    this.version = '',
    this.author = '',
    this.homepage = '',
  });

  factory SourceMeta.fromScript(String script) {
    String match(String pattern) {
      final m = RegExp(pattern).firstMatch(script);
      return m?.group(1)?.trim() ?? '';
    }
    return SourceMeta(
      name: match(r'@name\s+([^\n*]+)'),
      description: match(r'@description\s+([^\n*]+)'),
      version: match(r'@version\s+([^\n*]+)'),
      author: match(r'@author\s+([^\n*]+)'),
      homepage: match(r'@homepage\s+([^\n*]+)'),
    );
  }

  bool get isValid => name.isNotEmpty && version.isNotEmpty;

  @override
  String toString() => 'SourceMeta($name v$version by $author)';
}

/// 音源能力
@immutable
class SourceCapabilities {
  final Map<String, List<String>> sources; // source -> actions
  final Map<String, List<String>> qualitys; // source -> qualitys

  const SourceCapabilities({this.sources = const {}, this.qualitys = const {}});

  factory SourceCapabilities.fromJson(Map<String, dynamic> json) {
    final sources = <String, List<String>>{};
    final qualitys = <String, List<String>>{};
    final rawSources = json['sources'] as Map<String, dynamic>? ?? {};
    for (final entry in rawSources.entries) {
      final val = entry.value as Map<String, dynamic>;
      sources[entry.key] = (val['actions'] as List?)?.cast<String>() ?? [];
      qualitys[entry.key] = (val['qualitys'] as List?)?.cast<String>() ?? [];
    }
    return SourceCapabilities(sources: sources, qualitys: qualitys);
  }

  List<String> get availablePlatforms => sources.keys.toList();
  bool supports(String platform) => sources.containsKey(platform);
}

/// 音乐信息
@immutable
class MusicInfo {
  final String id;
  final String name;
  final String singer;
  final String album;
  final String source;
  final String? img;
  final int? interval;
  final String? hash;

  const MusicInfo({
    required this.id,
    required this.name,
    required this.singer,
    this.album = '',
    required this.source,
    this.img,
    this.interval,
    this.hash,
  });

  /// 内部稳定 ID (跨平台唯一)
  String get stableId => '${source}_$id';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'singer': singer,
        'album': album,
        'source': source,
        'img': img ?? '',
        'interval': interval ?? 0,
        'hash': hash ?? '',
      };

  factory MusicInfo.fromJson(Map<String, dynamic> j) => MusicInfo(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        singer: j['singer']?.toString() ?? '',
        album: j['album']?.toString() ?? '',
        source: j['source']?.toString() ?? '',
        img: j['img']?.toString(),
        interval: j['interval'] as int?,
        hash: j['hash']?.toString(),
      );

  /// 转 LRC 标签 ID（用作歌词匹配）
  String get lrcId => '$singer-$name'.toLowerCase().replaceAll(RegExp(r'\s+'), '');
}

/// 请求类型
enum RequestAction { musicUrl, musicLyric, musicPic, search, topList, sheetInfo }

extension RequestActionExt on RequestAction {
  String get name => switch (this) {
        RequestAction.musicUrl => 'musicUrl',
        RequestAction.musicLyric => 'musicLyric',
        RequestAction.musicPic => 'musicPic',
        RequestAction.search => 'search',
        RequestAction.topList => 'topList',
        RequestAction.sheetInfo => 'sheetInfo',
      };
}

/// 异常类型
class SourceLoadException implements Exception {
  final String message;
  final Object? cause;
  const SourceLoadException(this.message, [this.cause]);

  @override
  String toString() => 'SourceLoadException: $message${cause != null ? ' (cause: $cause)' : ''}';
}

class SourceRequestException implements Exception {
  final RequestAction action;
  final String source;
  final String message;
  const SourceRequestException(this.action, this.source, this.message);

  @override
  String toString() => 'SourceRequestException($source.${action.name}): $message';
}

/// 洛雪音源沙箱 — flutter_js 实现
///
/// 负责加载洛雪音源 JS 脚本，在 QuickJS 沙箱中执行，
/// 通过注入的 lx 全局对象与音源脚本通信。
class SourceEngine {
  final JavascriptRuntime _js;
  final Dio _dio;

  SourceMeta? meta;
  SourceCapabilities? capabilities;
  bool _inited = false;

  // 状态管理
  final _initCompleter = Completer<Map<String, dynamic>?>();
  final _requestCompleters = <String, Completer<dynamic>>{};

  // 资源管理
  Timer? _initTimeoutTimer;

  // 配置
  static const Duration _initTimeout = Duration(seconds: 10);
  static const Duration _requestTimeout = Duration(seconds: 30);

  SourceEngine({JavascriptRuntime? jsRuntime, Dio? dio})
      : _js = jsRuntime ?? getJavascriptRuntime(forceJavascriptCoreOnAndroid: false),
        _dio = dio ?? Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
            ));

  // ============================================================
  // 初始化与加载
  // ============================================================

  /// 初始化 Dart 侧消息桥
  void _setupBridge() {
    // 接收 init 事件
    _js.onMessage('lx_send', _handleSendMessage);
    // 接收 HTTP 请求
    _js.onMessage('lx_request', _handleRequestMessage);
    // 接收 crypto 调用
    _js.onMessage('lx_crypto', _handleCryptoMessage);
    // 接收 buffer 调用
    _js.onMessage('lx_buffer', _handleBufferMessage);
    // 接收 lx_call 响应
    _js.onMessage('lx_call_response', _handleCallResponse);
  }

  /// 注入 lx polyfill
  Future<void> _injectPolyfill() async {
    final polyfill = await rootBundle.loadString('assets/polyfills/lx_bridge.js');
    _js.evaluate(polyfill);
  }

  /// 加载音源脚本
  Future<bool> loadFromScript(String script) async {
    if (script.trim().isEmpty) {
      throw const SourceLoadException('Script content is empty');
    }

    _setupBridge();

    try {
      await _injectPolyfill();
    } catch (e) {
      throw SourceLoadException('Failed to inject polyfill', e);
    }

    // 解析元数据
    meta = SourceMeta.fromScript(script);
    if (!meta!.isValid) {
      throw SourceLoadException('Script missing @name or @version metadata');
    }
    debugPrint('[SourceEngine] 音源元数据: $meta');

    // 设置 currentScriptInfo
    _js.evaluate(_buildCurrentScriptInfoScript(meta!));

    // 启动初始化超时定时器
    _initTimeoutTimer?.cancel();
    _initTimeoutTimer = Timer(_initTimeout, () {
      if (!_initCompleter.isCompleted) {
        debugPrint('[SourceEngine] 音源未在 ${_initTimeout.inSeconds} 秒内调用 lx.send("inited")');
        _initCompleter.complete(null);
      }
    });

    // 执行音源脚本
    debugPrint('[SourceEngine] 正在执行音源脚本...');
    try {
      _js.evaluate(script);
    } catch (err) {
      throw SourceLoadException('Script execution failed', err);
    }

    // 等待 init 事件
    try {
      final initResult = await _initCompleter.future;
      _initTimeoutTimer?.cancel();

      if (initResult != null) {
        capabilities = SourceCapabilities.fromJson(initResult);
        _inited = true;
        debugPrint('[SourceEngine] ✅ 初始化成功: ${capabilities!.availablePlatforms}');
      } else {
        debugPrint('[SourceEngine] ⚠️ 初始化超时，音源可能仍可用');
      }
    } catch (e) {
      throw SourceLoadException('Init handler failed', e);
    }
    return _inited;
  }

  Future<bool> loadFromUrl(String url) async {
    if (url.isEmpty) {
      throw const SourceLoadException('URL is empty');
    }
    try {
      final response = await _dio.get<String>(url);
      if (response.statusCode != 200) {
        throw SourceLoadException('HTTP ${response.statusCode}');
      }
      return loadFromScript(response.data ?? '');
    } on DioException catch (e) {
      throw SourceLoadException('Network error: ${e.message}', e);
    }
  }

  String _buildCurrentScriptInfoScript(SourceMeta m) => '''
    globalThis.lx = globalThis.lx || {};
    globalThis.lx.currentScriptInfo = {
      name: ${jsonEncode(m.name)},
      description: ${jsonEncode(m.description)},
      version: ${jsonEncode(m.version)},
      author: ${jsonEncode(m.author)},
      homepage: ${jsonEncode(m.homepage)},
    };
    1
  ''';

  // ============================================================
  // 消息处理 (从 JS 沙箱)
  // ============================================================

  void _handleSendMessage(dynamic args) {
    try {
      final eventName = args[0] as String?;
      final dataJson = args[1] as String?;
      switch (eventName) {
        case 'inited':
          if (dataJson != null && !_initCompleter.isCompleted) {
            final data = jsonDecode(dataJson) as Map<String, dynamic>;
            _initCompleter.complete(data);
          }
          break;
        case 'updateAlert':
          debugPrint('[SourceEngine] 音源更新提示: $dataJson');
          break;
      }
    } catch (e) {
      debugPrint('[SourceEngine] onMessage error: $e');
    }
  }

  void _handleRequestMessage(dynamic args) {
    try {
      final url = args[0] as String;
      final optionsJson = args[1] as String? ?? '{}';
      final uuid = args[2] as String;
      final options = jsonDecode(optionsJson) as Map<String, dynamic>;
      _doHttpRequest(url, options, uuid);
    } catch (e) {
      debugPrint('[SourceEngine] request error: $e');
    }
  }

  void _handleCryptoMessage(dynamic args) {
    try {
      final action = args[0] as String;
      final paramsJson = args[1] as String? ?? '{}';
      final uuid = args[2] as String;
      try {
        final result = _handleCrypto(action, paramsJson);
        _js.sendMessage(channelName: 'lx_crypto_response', args: [uuid, 'null', result]);
      } catch (e) {
        _js.sendMessage(channelName: 'lx_crypto_response', args: [uuid, e.toString(), '']);
      }
    } catch (e) {
      debugPrint('[SourceEngine] crypto error: $e');
    }
  }

  void _handleBufferMessage(dynamic args) {
    try {
      final action = args[0] as String;
      final paramsJson = args[1] as String? ?? '{}';
      final uuid = args[2] as String;
      try {
        final result = _handleBuffer(action, paramsJson);
        _js.sendMessage(channelName: 'lx_buffer_response', args: [uuid, 'null', result]);
      } catch (e) {
        _js.sendMessage(channelName: 'lx_buffer_response', args: [uuid, e.toString(), '']);
      }
    } catch (e) {
      debugPrint('[SourceEngine] buffer error: $e');
    }
  }

  void _handleCallResponse(dynamic args) {
    try {
      final uuid = args[0] as String?;
      final error = args[1] as String?;
      final dataJson = args[2] as String?;
      if (uuid == null) return;

      final completer = _requestCompleters.remove(uuid);
      if (completer == null) return;

      if (error != null && error != 'null') {
        completer.completeError(Exception(error));
      } else {
        completer.complete(dataJson == 'null' || dataJson == null
            ? null
            : jsonDecode(dataJson));
      }
    } catch (e) {
      debugPrint('[SourceEngine] call response error: $e');
    }
  }

  Future<void> _doHttpRequest(String url, Map<String, dynamic> options, String uuid) async {
    try {
      final response = await _dio.request(
        url,
        data: options['body'],
        options: Options(
          method: (options['method'] as String?)?.toUpperCase() ?? 'GET',
          headers: Map<String, dynamic>.from(options['headers'] as Map? ?? {}),
          sendTimeout: Duration(milliseconds: options['timeout'] as int? ?? 60000),
          receiveTimeout: Duration(milliseconds: options['timeout'] as int? ?? 60000),
          responseType: ResponseType.plain,
          validateStatus: (_) => true,
        ),
      );
      final responseJson = jsonEncode({
        'statusCode': response.statusCode,
        'headers': response.headers.map,
        'body': response.data.toString(),
      });
      _js.sendMessage(
        channelName: 'lx_request_response',
        args: [uuid, 'null', responseJson],
      );
    } catch (e) {
      _js.sendMessage(
        channelName: 'lx_request_response',
        args: [uuid, e.toString(), 'null'],
      );
    }
  }

  // ============================================================
  // 加密 / 缓冲区 / zlib polyfill
  // ============================================================

  String _handleCrypto(String action, String paramsJson) {
    final params = jsonDecode(paramsJson) as Map<String, dynamic>;
    switch (action) {
      case 'aesEncrypt':
        final key = encrypt_pkg.Key(_b64decodeBytes(params['key']));
        final iv = params['iv'] != null
            ? encrypt_pkg.IV(_b64decodeBytes(params['iv']))
            : encrypt_pkg.IV.fromLength(16);
        final e = encrypt_pkg.Encrypter(encrypt_pkg.AES(key, mode: encrypt_pkg.AESMode.cbc));
        return e.encrypt(utf8.decode(_b64decodeBytes(params['buffer'])), iv: iv).base64;
      case 'aesDecrypt':
        final key = encrypt_pkg.Key(_b64decodeBytes(params['key']));
        final iv = params['iv'] != null
            ? encrypt_pkg.IV(_b64decodeBytes(params['iv']))
            : encrypt_pkg.IV.fromLength(16);
        final e = encrypt_pkg.Encrypter(encrypt_pkg.AES(key, mode: encrypt_pkg.AESMode.cbc));
        return base64Encode(utf8.encode(
            e.decrypt64(base64Encode(_b64decodeBytes(params['buffer'])), iv: iv)));
      case 'randomBytes':
        // 使用加密安全随机数
        final size = params['size'] as int;
        return base64Encode(_secureRandomBytes(size));
      case 'md5':
        return crypto_lib.md5.convert(utf8.encode(params['str'] as String)).toString();
      case 'sha256':
        return crypto_lib.sha256.convert(utf8.encode(params['str'] as String)).toString();
      default:
        throw SourceLoadException('Unknown crypto action: $action');
    }
  }

  String _handleBuffer(String action, String paramsJson) {
    final params = jsonDecode(paramsJson) as Map<String, dynamic>;
    switch (action) {
      case 'from':
        return base64Encode(utf8.encode(params['data'] as String));
      case 'bufToString':
        return utf8.decode(_b64decodeBytes(params['buffer']));
      case 'newBuffer':
        return base64Encode(Uint8List(params['size'] as int));
      default:
        throw SourceLoadException('Unknown buffer action: $action');
    }
  }

  /// 加密安全随机数
  static final math.Random _secureRng = math.Random.secure();
  Uint8List _secureRandomBytes(int size) {
    final bytes = Uint8List(size);
    for (var i = 0; i < size; i++) {
      bytes[i] = _secureRng.nextInt(256);
    }
    return bytes;
  }

  Uint8List _b64decodeBytes(dynamic b64) => base64Decode(b64 as String);

  // ============================================================
  // 播放器调用音源
  // ============================================================

  /// 发起 request（用 evaluate 调用音源脚本注册的 handler）
  Future<dynamic> callRequest({
    required String source,
    required RequestAction action,
    required Map<String, dynamic> info,
  }) async {
    if (!_inited) {
      throw SourceRequestException(action, source, 'Source not initialized');
    }
    if (!capabilities!.supports(source)) {
      throw SourceRequestException(action, source, 'Source does not support platform $source');
    }

    final requestJson = jsonEncode({'source': source, 'action': action.name, 'info': info});
    final uuid = 'req_${DateTime.now().microsecondsSinceEpoch}_${_requestCompleters.length}';

    final completer = Completer<dynamic>();
    _requestCompleters[uuid] = completer;

    // 调用 JS 端注册的 handler
    final escapedJson = _escapeJsString(requestJson);
    _js.evaluate("""
      (async () => {
        try {
          if (typeof globalThis.__lxRequestHandler === 'function') {
            const result = await globalThis.__lxRequestHandler(JSON.parse('$escapedJson'));
            DART_TO_QUICKJS_CHANNEL_sendMessage('lx_call_response', JSON.stringify(['$uuid', 'null', JSON.stringify(result)]));
          } else {
            DART_TO_QUICKJS_CHANNEL_sendMessage('lx_call_response', JSON.stringify(['$uuid', 'No request handler registered', 'null']));
          }
        } catch (e) {
          DART_TO_QUICKJS_CHANNEL_sendMessage('lx_call_response', JSON.stringify(['$uuid', e.message || String(e), 'null']));
        }
      })();
      1
    """);

    try {
      return await completer.future.timeout(_requestTimeout);
    } on TimeoutException {
      _requestCompleters.remove(uuid);
      throw SourceRequestException(action, source, 'Request timeout after ${_requestTimeout.inSeconds}s');
    }
  }

  Future<String?> getMusicUrl({
    required String source,
    required MusicInfo music,
    String quality = '128k',
  }) async {
    final result = await callRequest(
      source: source,
      action: RequestAction.musicUrl,
      info: {'type': quality, 'musicInfo': music.toJson()},
    );
    if (result is! Map) return null;
    return result['url'] as String?;
  }

  Future<String?> getMusicLyric({
    required String source,
    required MusicInfo music,
  }) async {
    final result = await callRequest(
      source: source,
      action: RequestAction.musicLyric,
      info: {'musicInfo': music.toJson()},
    );
    if (result is! Map) return null;
    return (result['lyric'] ?? result['data']?['lyric']) as String?;
  }

  Future<String?> getMusicPic({
    required String source,
    required MusicInfo music,
  }) async {
    final result = await callRequest(
      source: source,
      action: RequestAction.musicPic,
      info: {'musicInfo': music.toJson()},
    );
    if (result is! Map) return null;
    return (result['url'] ?? result['data']) as String?;
  }

  Future<List<MusicInfo>> search({
    required String source,
    required String keyword,
    int page = 1,
    int limit = 30,
  }) async {
    if (keyword.trim().isEmpty) return [];
    final result = await callRequest(
      source: source,
      action: RequestAction.search,
      info: {'keyword': keyword, 'page': page, 'limit': limit},
    );
    if (result is! Map) return [];
    final list = (result['list'] as List?) ?? [];
    return list.whereType<Map>().map((m) => MusicInfo.fromJson({
          ...Map<String, dynamic>.from(m),
          'source': source,
        })).toList();
  }

  /// 转义用于嵌入到 JS 单引号字符串字面量中的内容。
  /// 注意必须转义 U+2028 / U+2029（行/段分隔符）——它们在 JSON 里合法，
  /// 但在 JS 字符串字面量中是非法的，会让 evaluate 直接抛语法错误。
  String _escapeJsString(String s) => s
      .replaceAll('\\', '\\\\')
      .replaceAll("'", "\\'")
      .replaceAll('\n', '\\n')
      .replaceAll('\r', '\\r')
      .replaceAll(' ', '\\u2028')
      .replaceAll(' ', '\\u2029');

  // ============================================================
  // 资源清理
  // ============================================================

  void dispose() {
    _initTimeoutTimer?.cancel();
    // 取消所有 pending 请求
    for (final c in _requestCompleters.values) {
      if (!c.isCompleted) {
        c.completeError(const SourceRequestException(
          RequestAction.musicUrl, '', 'Engine disposed'));
      }
    }
    _requestCompleters.clear();
    _js.dispose();
  }
}
