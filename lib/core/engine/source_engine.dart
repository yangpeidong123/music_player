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
  final Map<String, List<String>> sources;
  final Map<String, List<String>> qualitys;

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

/// 音乐信息
class MusicInfo {
  final String id;
  final String name;
  final String singer;
  final String album;
  final String source;
  final String? img;
  final int? interval;
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
        'id': id, 'name': name, 'singer': singer, 'album': album,
        'source': source, 'img': img ?? '', 'interval': interval ?? 0, 'hash': hash ?? '',
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

/// 洛雪音源沙箱 — flutter_js 实现
class SourceEngine {
  final JavascriptRuntime _js;
  final Dio _dio;

  SourceMeta? meta;
  SourceCapabilities? capabilities;
  bool _inited = false;

  // 等待 init 事件
  final _initCompleter = Completer<Map<String, dynamic>?>();

  // 等待 request 响应 (uuid -> completer)
  final _requestCompleters = <String, Completer<dynamic>>{};

  SourceEngine({JavascriptRuntime? jsRuntime, Dio? dio})
      : _js = jsRuntime ?? getJavascriptRuntime(forceJavascriptCoreOnAndroid: false),
        _dio = dio ?? Dio();

  /// 初始化 Dart 侧消息桥
  void _setupBridge() {
    // 接收 init 事件
    _js.onMessage('lx_send', (dynamic args) {
      try {
        final eventName = args[0] as String?;
        final dataJson = args[1] as String?;
        if (eventName == 'inited' && dataJson != null) {
          final data = jsonDecode(dataJson) as Map<String, dynamic>;
          if (!_initCompleter.isCompleted) _initCompleter.complete(data);
        }
      } catch (e) {
        print('[SourceEngine] onMessage error: $e');
      }
    });

    // 接收 request 调用 (音源脚本调 lx.request)
    _js.onMessage('lx_request', (dynamic args) {
      try {
        final url = args[0] as String;
        final optionsJson = args[1] as String? ?? '{}';
        final uuid = args[2] as String;
        final options = jsonDecode(optionsJson) as Map<String, dynamic>;
        _doHttpRequest(url, options, uuid);
      } catch (e) {
        print('[SourceEngine] request error: $e');
      }
    });

    // 接收 crypto 调用
    _js.onMessage('lx_crypto', (dynamic args) {
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
        print('[SourceEngine] crypto error: $e');
      }
    });

    // 接收 buffer 调用
    _js.onMessage('lx_buffer', (dynamic args) {
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
        print('[SourceEngine] buffer error: $e');
      }
    });
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
      final body = response.data.toString();
      final responseJson = jsonEncode({
        'statusCode': response.statusCode,
        'headers': response.headers.map,
        'body': body,
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

  /// 注入 lx polyfill 到沙箱
  Future<void> _injectPolyfill() async {
    final polyfill = await rootBundle.loadString('assets/polyfills/lx_bridge.js');
    _js.evaluate(polyfill);
  }

  /// 加载音源脚本
  Future<bool> loadFromScript(String script) async {
    _setupBridge();
    await _injectPolyfill();

    // 解析元数据
    meta = SourceMeta.fromScript(script);
    print('[SourceEngine] 音源元数据: $meta');

    // 设置 currentScriptInfo
    _js.evaluate('''
      globalThis.lx = globalThis.lx || {};
      globalThis.lx.currentScriptInfo = {
        name: ${jsonEncode(meta!.name)},
        description: ${jsonEncode(meta!.description)},
        version: ${jsonEncode(meta!.version)},
        author: ${jsonEncode(meta!.author)},
        homepage: ${jsonEncode(meta!.homepage)},
      };
      1
    ''');

    // 执行音源脚本
    print('[SourceEngine] 正在执行音源脚本...');
    try {
      _js.evaluate(script);
    } catch (err) {
      print('[SourceEngine] 音源脚本执行失败: $err');
      return false;
    }

    // 等待 inited 事件（最多 10 秒）
    try {
      final initResult = await _initCompleter.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          print('[SourceEngine] ⚠️ 音源未在 10 秒内调用 lx.send("inited")');
          return null;
        },
      );
      if (initResult != null) {
        capabilities = SourceCapabilities.fromJson(initResult);
        _inited = true;
        print('[SourceEngine] ✅ 初始化成功');
      }
    } catch (e) {
      print('[SourceEngine] 初始化异常: $e');
    }
    return _inited;
  }

  Future<bool> loadFromUrl(String url) async {
    final response = await _dio.get<String>(url);
    if (response.statusCode != 200) {
      throw Exception('下载失败: HTTP ${response.statusCode}');
    }
    return loadFromScript(response.data!);
  }

  // ============================================================
  // 加密 / 缓冲区 / zlib polyfill
  // ============================================================

  String _handleCrypto(String action, String paramsJson) {
    final params = jsonDecode(paramsJson) as Map<String, dynamic>;
    switch (action) {
      case 'aesEncrypt':
        final key = encrypt.Key(Uint8List.fromList(_b64decode(params['key'])));
        final iv = params['iv'] != null
            ? encrypt.IV(Uint8List.fromList(_b64decode(params['iv'])))
            : encrypt.IV.fromLength(16);
        final e = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));
        return base64Encode(e.encryptBytes(_b64decode(params['buffer']), iv: iv));
      case 'aesDecrypt':
        final key = encrypt.Key(Uint8List.fromList(_b64decode(params['key'])));
        final iv = params['iv'] != null
            ? encrypt.IV(Uint8List.fromList(_b64decode(params['iv'])))
            : encrypt.IV.fromLength(16);
        final e = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));
        return base64Encode(e.decrypt(
          encrypt.Encrypted.fromBase64(base64Encode(_b64decode(params['buffer']))), iv: iv).bytes);
      case 'randomBytes':
        return base64Encode(Uint8List(params['size'] as int));
      case 'md5':
        return md5.convert(utf8.encode(params['str'] as String)).toString();
      case 'sha256':
        return sha256.convert(utf8.encode(params['str'] as String)).toString();
      default:
        throw Exception('Unknown crypto: $action');
    }
  }

  String _handleBuffer(String action, String paramsJson) {
    final params = jsonDecode(paramsJson) as Map<String, dynamic>;
    switch (action) {
      case 'from':
        return base64Encode(utf8.encode(params['data'] as String));
      case 'bufToString':
        return utf8.decode(_b64decode(params['buffer']));
      case 'newBuffer':
        return base64Encode(Uint8List(params['size'] as int));
      default:
        throw Exception('Unknown buffer: $action');
    }
  }

  String _handleZlib(String action, String b64) {
    final data = _b64decode(b64);
    switch (action) {
      case 'inflate':
        return base64Encode(ZLibDecoder().decodeBytes(data));
      case 'deflate':
        // archive 5.x: ZLibEncoder().encode(List<int>) returns List<int>
        return base64Encode(ZLibEncoder().encode(data));
      default:
        throw Exception('Unknown zlib: $action');
    }
  }

  List<int> _b64decode(String b64) => base64Decode(b64);

  // ============================================================
  // 播放器调用音源
  // ============================================================

  /// 发起 request（用 evaluate 调用音源脚本注册的 handler）
  Future<dynamic> callRequest({
    required String source,
    required RequestAction action,
    required Map<String, dynamic> info,
  }) async {
    final requestJson = jsonEncode({'source': source, 'action': action.name, 'info': info});
    final uuid = 'req_${DateTime.now().millisecondsSinceEpoch}_${_requestCompleters.length}';

    final completer = Completer<dynamic>();
    _requestCompleters[uuid] = completer;

    // 注册响应接收
    _js.onMessage('lx_call_response', (dynamic args) {
      try {
        final respUuid = args[0] as String;
        final error = args[1] as String?;
        final dataJson = args[2] as String?;
        if (_requestCompleters.containsKey(respUuid)) {
          final c = _requestCompleters.remove(respUuid)!;
          if (error != null && error != 'null') {
            c.completeError(Exception(error));
          } else {
            c.complete(dataJson == 'null' ? null : jsonDecode(dataJson!));
          }
        }
      } catch (e) {
        print('[SourceEngine] call response error: $e');
      }
    });

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

    return completer.future.timeout(const Duration(seconds: 30));
  }

  Future<String?> getMusicUrl({required String source, required MusicInfo music, String quality = '128k'}) async {
    final result = await callRequest(source: source, action: RequestAction.musicUrl, info: {'type': quality, 'musicInfo': music.toJson()});
    return result?['url'] as String?;
  }

  Future<String?> getMusicLyric({required String source, required MusicInfo music}) async {
    final result = await callRequest(source: source, action: RequestAction.musicLyric, info: {'musicInfo': music.toJson()});
    return result?['lyric'] as String?;
  }

  Future<String?> getMusicPic({required String source, required MusicInfo music}) async {
    final result = await callRequest(source: source, action: RequestAction.musicPic, info: {'musicInfo': music.toJson()});
    return result?['url'] as String?;
  }

  Future<List<MusicInfo>> search({required String source, required String keyword, int page = 1, int limit = 30}) async {
    final result = await callRequest(source: source, action: RequestAction.search, info: {'keyword': keyword, 'page': page, 'limit': limit});
    final list = result?['list'] as List? ?? [];
    return list.map((item) {
      final m = item as Map<String, dynamic>;
      return MusicInfo(
        id: m['id']?.toString() ?? '', name: m['name']?.toString() ?? '',
        singer: m['singer']?.toString() ?? '', album: m['album']?.toString() ?? '',
        source: source, img: m['img']?.toString(),
        interval: m['interval'] as int?, hash: m['hash']?.toString(),
      );
    }).toList();
  }

  String _escapeJsString(String s) => s
      .replaceAll('\\', '\\\\')
      .replaceAll("'", "\\'")
      .replaceAll('\n', '\\n')
      .replaceAll('\r', '\\r');

  void dispose() => _js.dispose();
}
