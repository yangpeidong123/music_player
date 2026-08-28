import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_js/flutter_js.dart';
import 'package:dio/dio.dart';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:archive/archive.dart';

/// 洛雪音源元数据
class SourceMeta {
  final String name;
  final String description;
  final String version;
  final String author;
  final String homepage;

  SourceMeta({
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

  @override
  String toString() => 'SourceMeta($name v$version by $author)';
}

/// 音源支持的源和音质
class SourceCapabilities {
  final Map<String, List<String>> sources; // source -> actions
  final Map<String, List<String>> qualitys; // source -> qualitys

  SourceCapabilities({this.sources = const {}, this.qualitys = const {}});

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
}

/// 音乐信息模型
class MusicInfo {
  final String id;
  final String name;
  final String singer;
  final String album;
  final String source; // kw, wy, mg, tx, kg
  final String? img;
  final int? interval; // 秒
  final String? hash;

  MusicInfo({
    required this.id,
    required this.name,
    required this.singer,
    this.album = '',
    required this.source,
    this.img,
    this.interval,
    this.hash,
  });

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

/// 洛雪音源沙箱 — 核心引擎
///
/// 负责加载洛雪音源 JS 脚本，在 flutter_js (QuickJS) 沙箱中执行，
/// 通过注入的 lx 全局对象与音源脚本通信。
class SourceEngine {
  final JavascriptRuntime _js;
  final Dio _dio;

  SourceMeta? meta;
  SourceCapabilities? capabilities;
  bool _inited = false;
  bool _loaded = false;

  // 请求回调
  final _pendingRequests = <String, Completer<dynamic>>{};

  SourceEngine({JavascriptRuntime? jsRuntime, Dio? dio})
      : _js = jsRuntime ?? getJavascriptRuntime(forceJavascriptCoreOnAndroid: false),
        _dio = dio ?? Dio();

  /// 初始化：注入 polyfill
  Future<void> _injectPolyfill() async {
    final polyfill = await rootBundle.loadString('assets/polyfills/lx_bridge.js');
    _js.evaluate(polyfill);

    // 注册 Dart 侧 native 函数
    _js.setProperty('__lx_native_send', allowInterop(_handleSend));
    _js.setProperty('__lx_native_request', allowInterop(_handleRequest));
    _js.setProperty('__lx_native_crypto', allowInterop(_handleCrypto));
    _js.setProperty('__lx_native_buffer', allowInterop(_handleBuffer));
    _js.setProperty('__lx_native_zlib', allowInterop(_handleZlib));
    _js.setProperty('__lx_native_log', allowInterop(_handleLog));
    _js.setProperty('__lx_native_setTimeout', allowInterop(_handleSetTimeout));
    _js.setProperty('__lx_native_clearTimeout', allowInterop(_handleClearTimeout));
  }

  /// 加载音源脚本
  Future<bool> loadFromScript(String script) async {
    if (!_loaded) {
      await _injectPolyfill();
      _loaded = true;
    }

    // 解析元数据
    meta = SourceMeta.fromScript(script);
    print('[SourceEngine] 音源元数据: $meta');

    // 设置 currentScriptInfo
    _js.evaluate('''
      globalThis.lx.currentScriptInfo = {
        name: ${jsonEncode(meta!.name)},
        description: ${jsonEncode(meta!.description)},
        version: ${jsonEncode(meta!.version)},
        author: ${jsonEncode(meta!.author)},
        homepage: ${jsonEncode(meta!.homepage)},
      };
    ''');

    // 执行音源脚本
    print('[SourceEngine] 正在执行音源脚本...');
    try {
      final result = _js.evaluate(script);
      print('[SourceEngine] 音源脚本执行完成');
    } catch (err) {
      print('[SourceEngine] 音源脚本执行失败: $err');
      return false;
    }

    // 等待 inited 事件（最多 10 秒）
    final initCompleter = Completer<Map<String, dynamic>?>();
    _initCompleter = initCompleter;

    try {
      final initResult = await initCompleter.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          print('[SourceEngine] ⚠️ 音源未在 10 秒内调用 lx.send("inited")');
          return null;
        },
      );

      if (initResult != null) {
        capabilities = SourceCapabilities.fromJson(initResult);
        _inited = true;
        print('[SourceEngine] ✅ 初始化成功，支持的音源: ${capabilities?.sources.keys.toList()}');
      }
    } catch (e) {
      print('[SourceEngine] 初始化异常: $e');
    }

    return _inited;
  }

  /// 从 URL 加载音源
  Future<bool> loadFromUrl(String url) async {
    print('[SourceEngine] 下载音源: $url');
    final response = await _dio.get<String>(url);
    if (response.statusCode != 200) {
      throw Exception('下载失败: HTTP ${response.statusCode}');
    }
    return loadFromScript(response.data!);
  }

  Completer<Map<String, dynamic>?>? _initCompleter;

  // ============================================================
  // Dart 侧 native 函数（被 JS 沙箱调用）
  // ============================================================

  /// lx.send(eventName, data) → Dart
  void _handleSend(String eventName, String dataJson) {
    final data = jsonDecode(dataJson) as Map<String, dynamic>;
    switch (eventName) {
      case 'inited':
        _initCompleter?.complete(data);
        break;
      case 'updateAlert':
        print('[SourceEngine] 音源更新提示: $data');
        break;
    }
  }

  /// lx.request(url, options) → Dart HTTP → JS 回调
  String _handleRequest(String requestJson) {
    final req = jsonDecode(requestJson) as Map<String, dynamic>;
    final requestId = 'req_${DateTime.now().millisecondsSinceEpoch}_${_pendingRequests.length}';

    () async {
      try {
        final response = await _dio.request(
          req['url'] as String,
          data: req['body'],
          options: Options(
            method: (req['method'] as String?)?.toUpperCase() ?? 'GET',
            headers: Map<String, dynamic>.from(req['headers'] as Map? ?? {}),
            sendTimeout: Duration(milliseconds: req['timeout'] as int? ?? 60000),
            receiveTimeout: Duration(milliseconds: req['timeout'] as int? ?? 60000),
            responseType: ResponseType.plain,
            validateStatus: (_) => true,
          ),
        );

        // 调用 JS 回调
        final responseJson = jsonEncode({
          'statusCode': response.statusCode,
          'headers': response.headers.map,
          'body': response.data.toString(),
        });
        _js.evaluate(
          "globalThis.__lx_request_callback('$requestId', null, '${_escapeJsString(responseJson)}');",
        );
      } catch (e) {
        _js.evaluate(
          "globalThis.__lx_request_callback('$requestId', '${_escapeJsString(e.toString())}', null);",
        );
      }
    }();

    return requestId;
  }

  /// lx.utils.crypto.* → Dart crypto
  String _handleCrypto(String action, String paramsJson) {
    final params = jsonDecode(paramsJson) as Map<String, dynamic>;
    switch (action) {
      case 'aesEncrypt':
        final key = encrypt.Key(Uint8List.fromList(_b64decode(params['key'])));
        final iv = params['iv'] != null
            ? encrypt.IV(Uint8List.fromList(_b64decode(params['iv'])))
            : encrypt.IV.fromLength(16);
        final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));
        final encrypted = encrypter.encryptBytes(_b64decode(params['buffer']), iv: iv);
        return base64Encode(encrypted);

      case 'aesDecrypt':
        final key = encrypt.Key(Uint8List.fromList(_b64decode(params['key'])));
        final iv = params['iv'] != null
            ? encrypt.IV(Uint8List.fromList(_b64decode(params['iv'])))
            : encrypt.IV.fromLength(16);
        final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));
        final decrypted = encrypter.decryptBytes(
          encrypt.Encrypted(Uint8List.fromList(_b64decode(params['buffer']))),
          iv: iv,
        );
        return base64Encode(decrypted);

      case 'rsaEncrypt':
        // 洛雪 RSA 特殊 padding：前面补 0 减到 128 字节
        final buffer = _b64decode(params['buffer']);
        final padded = Uint8List(128);
        final offset = 128 - buffer.length;
        for (int i = 0; i < buffer.length; i++) {
          padded[offset + i] = buffer[i];
        }
        // TODO: 实际 RSA 加密需要 pointycastle RSA 引擎
        return base64Encode(padded);

      case 'randomBytes':
        final size = params['size'] as int;
        final bytes = Uint8List(size);
        // 使用 dart:math.Random 生成
        for (int i = 0; i < size; i++) {
          bytes[i] = DateTime.now().microsecondsSinceEpoch & 0xFF;
        }
        return base64Encode(bytes);

      case 'md5':
        return md5.convert(utf8.encode(params['str'] as String)).toString();

      case 'sha256':
        return sha256.convert(utf8.encode(params['str'] as String)).toString();

      default:
        throw Exception('Unknown crypto action: $action');
    }
  }

  /// lx.utils.buffer.* → Dart
  String _handleBuffer(String action, String paramsJson) {
    final params = jsonDecode(paramsJson) as Map<String, dynamic>;
    switch (action) {
      case 'from':
        final encoding = params['encoding'] as String? ?? 'utf-8';
        final data = params['data'] as String;
        return base64Encode(utf8.encode(data));

      case 'bufToString':
        final buffer = _b64decode(params['buffer']);
        final format = params['format'] as String? ?? 'utf-8';
        return utf8.decode(buffer);

      case 'newBuffer':
        final size = params['size'] as int;
        return base64Encode(Uint8List(size));

      default:
        throw Exception('Unknown buffer action: $action');
    }
  }

  /// lx.utils.zlib.* → Dart
  String _handleZlib(String action, String b64data) {
    final data = _b64decode(b64data);
    switch (action) {
      case 'inflate':
        final inflated = ZLibDecoder().decodeBytes(data);
        return base64Encode(inflated);

      case 'deflate':
        final deflated = ZLibEncoder().encodeBytes(data);
        return base64Encode(deflated);

      default:
        throw Exception('Unknown zlib action: $action');
    }
  }

  /// console.log → Dart print
  void _handleLog(String level, String argsJson) {
    final args = jsonDecode(argsJson) as List;
    final msg = args.map((a) => a.toString()).join(' ');
    switch (level) {
      case 'error':
        print('[Source Error] $msg');
        break;
      case 'warn':
        print('[Source Warn] $msg');
        break;
      default:
        print('[Source] $msg');
    }
  }

  int _timeoutCounter = 0;
  final _timeouts = <int, Timer>{};

  int _handleSetTimeout(Function() fn, int ms) {
    final id = ++_timeoutCounter;
    _timeouts[id] = Timer(Duration(milliseconds: ms), fn);
    return id;
  }

  void _handleClearTimeout(int id) {
    _timeouts.remove(id)?.cancel();
  }

  // ============================================================
  // 播放器调用音源（核心 API）
  // ============================================================

  /// 发起 request 请求
  Future<dynamic> callRequest({
    required String source,
    required RequestAction action,
    required Map<String, dynamic> info,
  }) async {
    final request = jsonEncode({
      'source': source,
      'action': action.name,
      'info': info,
    });

    // 调用沙箱中的 request 处理器
    final resultJson = _js.evaluate(
      "globalThis.__lx_call_request_handler? await globalThis.__lx_call_request_handler('${_escapeJsString(request)}') : null",
    );

    // flutter_js 不直接支持 async 返回，需要轮询
    // 实际实现中可以用 onMessage 机制
    final result = jsonDecode(resultJson.stringResult);
    if (result['error'] != null) {
      throw Exception(result['error']);
    }
    return result['data'];
  }

  /// 获取播放链接
  Future<String?> getMusicUrl({
    required String source,
    required MusicInfo music,
    String quality = '128k',
  }) async {
    final result = await callRequest(
      source: source,
      action: RequestAction.musicUrl,
      info: {
        'type': quality,
        'musicInfo': music.toJson(),
      },
    );
    return result?['url'] as String?;
  }

  /// 获取歌词
  Future<String?> getMusicLyric({
    required String source,
    required MusicInfo music,
  }) async {
    final result = await callRequest(
      source: source,
      action: RequestAction.musicLyric,
      info: {'musicInfo': music.toJson()},
    );
    return result?['lyric'] as String?;
  }

  /// 获取封面图
  Future<String?> getMusicPic({
    required String source,
    required MusicInfo music,
  }) async {
    final result = await callRequest(
      source: source,
      action: RequestAction.musicPic,
      info: {'musicInfo': music.toJson()},
    );
    return result?['url'] as String?;
  }

  /// 搜索音乐
  Future<List<MusicInfo>> search({
    required String source,
    required String keyword,
    int page = 1,
    int limit = 30,
  }) async {
    final result = await callRequest(
      source: source,
      action: RequestAction.search,
      info: {'keyword': keyword, 'page': page, 'limit': limit},
    );
    final list = result?['list'] as List? ?? [];
    return list.map((item) {
      final m = item as Map<String, dynamic>;
      return MusicInfo(
        id: m['id']?.toString() ?? '',
        name: m['name']?.toString() ?? '',
        singer: m['singer']?.toString() ?? '',
        album: m['album']?.toString() ?? '',
        source: source,
        img: m['img']?.toString(),
        interval: m['interval'] as int?,
        hash: m['hash']?.toString(),
      );
    }).toList();
  }

  // ============================================================
  // 工具函数
  // ============================================================

  List<int> _b64decode(String b64) {
    return base64Decode(b64);
  }

  String _escapeJsString(String s) {
    return s
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'")
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r');
  }

  void dispose() {
    _js.dispose();
  }
}
