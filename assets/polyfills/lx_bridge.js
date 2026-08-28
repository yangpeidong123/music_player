/**
 * LX Bridge Polyfill — 洛雪音源 lx 全局对象实现
 *
 * 适配 flutter_js 0.8.7 的消息传递机制：
 * - JS 调 Dart: sendMessage('channel', args)
 * - Dart 调 JS: 通过 evaluate() 执行 JS 代码，JS 端调 DART_TO_QUICKJS_CHANNEL_sendMessage
 *
 * 协议参考：lx-music-desktop/src/main/modules/userApi/renderer/preload.js
 */

;(function() {
  'use strict';

  var __NATIVE_sendMessage = (typeof sendMessage === 'function')
    ? sendMessage
    : (typeof DART_TO_QUICKJS_CHANNEL_sendMessage === 'function')
      ? function(channel, args) { DART_TO_QUICKJS_CHANNEL_sendMessage(channel, JSON.stringify(args)); }
      : function() { console.error('No sendMessage available'); };

  function jsonStringifySafe(obj) {
    try { return JSON.stringify(obj); } catch (e) { return 'null'; }
  }

  function base64Encode(bytes) {
    var binary = '';
    var arr = bytes instanceof ArrayBuffer ? new Uint8Array(bytes) : bytes;
    for (var i = 0; i < arr.length; i++) binary += String.fromCharCode(arr[i]);
    return btoa(binary);
  }

  function base64Decode(b64) {
    var binary = atob(b64);
    var bytes = new Uint8Array(binary.length);
    for (var i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return bytes.buffer;
  }

  // UUID 生成器（异步调用）
  var __asyncCallId = 0;
  var __asyncCallbacks = {};

  // ——————————————————————————————————————————————————————————
  // HTTP 请求桥 (lx_request → Dart dio)
  // ——————————————————————————————————————————————————————————
  function lxRequest(url, options, callback) {
    if (typeof options === 'function') { callback = options; options = {}; }
    options = options || {};
    var method = (options.method || 'get').toUpperCase();
    var headers = options.headers || {};
    var body = options.body || null;
    var timeout = options.timeout || 60000;

    var uuid = 'cb_' + (++__asyncCallId) + '_' + Date.now();

    // 注册回调（callback 将在 lx_request_response 收到时调用）
    __asyncCallbacks[uuid] = function(err, responseJson) {
      delete __asyncCallbacks[uuid];
      if (callback) {
        if (err && err !== 'null') {
          callback(new Error(err), null, null);
        } else {
          try {
            var res = typeof responseJson === 'string' ? JSON.parse(responseJson) : responseJson;
            var body = res.body;
            var bodyParsed = body;
            try { bodyParsed = JSON.parse(body); } catch (_) {}
            callback(null, {
              statusCode: res.statusCode,
              headers: res.headers,
              body: bodyParsed,
            }, body);
          } catch (e) {
            callback(new Error('parse response failed: ' + e.message), null, null);
          }
        }
      }
    };

    __NATIVE_sendMessage('lx_request', [url, jsonStringifySafe({
      method: method, headers: headers, body: body, timeout: timeout
    }), uuid]);
  }

  // ——————————————————————————————————————————————————————————
  // 加密桥 (lx_crypto → Dart crypto)
  // ——————————————————————————————————————————————————————————
  function lxCryptoAsync(action, params) {
    return new Promise(function(resolve, reject) {
      var uuid = 'cr_' + (++__asyncCallId) + '_' + Date.now();
      __asyncCallbacks[uuid] = function(err, result) {
        delete __asyncCallbacks[uuid];
        if (err && err !== 'null') reject(new Error(err));
        else resolve(result);
      };
      __NATIVE_sendMessage('lx_crypto', [action, jsonStringifySafe(params), uuid]);
    });
  }

  var utils = {
    crypto: {
      aesEncrypt: function(buffer, mode, key, iv) {
        return lxCryptoAsync('aesEncrypt', {
          buffer: base64Encode(buffer instanceof ArrayBuffer ? new Uint8Array(buffer) : buffer),
          mode: mode,
          key: base64Encode(key instanceof ArrayBuffer ? new Uint8Array(key) : key),
          iv: iv ? base64Encode(iv instanceof ArrayBuffer ? new Uint8Array(iv) : iv) : null,
        });
      },
      aesDecrypt: function(buffer, mode, key, iv) {
        return lxCryptoAsync('aesDecrypt', {
          buffer: base64Encode(buffer instanceof ArrayBuffer ? new Uint8Array(buffer) : buffer),
          mode: mode, key: base64Encode(key), iv: iv ? base64Encode(iv) : null,
        });
      },
      randomBytes: function(size) {
        return lxCryptoAsync('randomBytes', { size: size });
      },
      md5: function(str) {
        return lxCryptoAsync('md5', { str: str });
      },
      sha256: function(str) {
        return lxCryptoAsync('sha256', { str: str });
      },
    },
    buffer: {
      from: function(data, encoding) {
        return new Promise(function(resolve, reject) {
          var uuid = 'bf_' + (++__asyncCallId) + '_' + Date.now();
          __asyncCallbacks[uuid] = function(err, result) {
            delete __asyncCallbacks[uuid];
            if (err && err !== 'null') reject(new Error(err));
            else resolve(base64Decode(result));
          };
          __NATIVE_sendMessage('lx_buffer', ['from', jsonStringifySafe({ data: data, encoding: encoding || 'utf-8' }), uuid]);
        });
      },
      bufToString: function(buf, format) {
        return new Promise(function(resolve, reject) {
          var uuid = 'bs_' + (++__asyncCallId) + '_' + Date.now();
          __asyncCallbacks[uuid] = function(err, result) {
            delete __asyncCallbacks[uuid];
            if (err && err !== 'null') reject(new Error(err));
            else resolve(result);
          };
          __NATIVE_sendMessage('lx_buffer', ['bufToString', jsonStringifySafe({
            buffer: base64Encode(buf instanceof ArrayBuffer ? new Uint8Array(buf) : buf),
            format: format || 'utf-8',
          }), uuid]);
        });
      },
      newBuffer: function(size) {
        return new Promise(function(resolve, reject) {
          var uuid = 'bn_' + (++__asyncCallId) + '_' + Date.now();
          __asyncCallbacks[uuid] = function(err, result) {
            delete __asyncCallbacks[uuid];
            if (err && err !== 'null') reject(new Error(err));
            else resolve(base64Decode(result));
          };
          __NATIVE_sendMessage('lx_buffer', ['newBuffer', jsonStringifySafe({ size: size }), uuid]);
        });
      },
    },
  };

  // ——————————————————————————————————————————————————————————
  // lx 全局对象
  // ——————————————————————————————————————————————————————————
  var EVENT_NAMES = {
    request: 'request',
    inited: 'inited',
    updateAlert: 'updateAlert',
  };

  var __inited = false;
  var __updateAlertShown = false;

  globalThis.lx = {
    EVENT_NAMES: EVENT_NAMES,
    version: '2.0.0',
    env: 'flutter',
    currentScriptInfo: {
      name: '', description: '', version: '', author: '', homepage: '',
    },
    utils: utils,
    request: lxRequest,

    on: function(eventName, handler) {
      return new Promise(function(resolve, reject) {
        if (eventName === EVENT_NAMES.request) {
          globalThis.__lxRequestHandler = handler;
          resolve();
        } else {
          reject(new Error('Event not supported: ' + eventName));
        }
      });
    },

    send: function(eventName, data) {
      return new Promise(function(resolve, reject) {
        if (eventName === EVENT_NAMES.inited) {
          if (__inited) return reject(new Error('Script already inited'));
          __inited = true;
          __NATIVE_sendMessage('lx_send', [eventName, jsonStringifySafe(data)]);
          resolve();
        } else if (eventName === EVENT_NAMES.updateAlert) {
          if (__updateAlertShown) return reject(new Error('Update alert already shown'));
          __updateAlertShown = true;
          __NATIVE_sendMessage('lx_send', [eventName, jsonStringifySafe(data)]);
          resolve();
        } else {
          reject(new Error('Event not supported: ' + eventName));
        }
      });
    },
  };

  // 暴露 DART→JS 的消息接收器 (由 flutter_js 注入)
  // 当 Dart 调 DART_TO_QUICKJS_CHANNEL_sendMessage('lx_request_response', '[uuid, err, data]') 时
  if (typeof DART_TO_QUICKJS_CHANNEL_sendMessage === 'function') {
    // We can listen via globalThis; but for our async callbacks, the global __asyncCallbacks map is used
  }

  // 接收 Dart 调来的消息 (Dart 通过 evaluate 执行 DART_TO_QUICKJS_CHANNEL_sendMessage)
  // 我们 hook 一下 window/globalThis
  globalThis.__receiveDartMessage = function(channel, argsJson) {
    try {
      var args = JSON.parse(argsJson);
      if (channel === 'lx_request_response') {
        var uuid = args[0];
        var err = args[1];
        var data = args[2];
        if (__asyncCallbacks[uuid]) __asyncCallbacks[uuid](err, data);
      } else if (channel === 'lx_crypto_response' || channel === 'lx_buffer_response' || channel === 'lx_zlib_response') {
        var uuid = args[0];
        var err = args[1];
        var data = args[2];
        if (__asyncCallbacks[uuid]) __asyncCallbacks[uuid](err, data);
      }
    } catch (e) {
      console.error('__receiveDartMessage error:', e);
    }
  };

  // zlib stub (源码脚本可能调用 inflate/deflate, 暂用原生实现)
  utils.zlib = {
    inflate: function(buf) {
      return new Promise(function(resolve, reject) {
        try {
          // 使用浏览器原生 DecompressionStream
          if (typeof DecompressionStream === 'function') {
            var stream = new Response(new Blob([buf]).stream().pipeThrough(new DecompressionStream('deflate')));
            stream.arrayBuffer().then(function(ab) { resolve(new Uint8Array(ab)); }).catch(reject);
          } else {
            reject(new Error('zlib.inflate not supported in this runtime'));
          }
        } catch (e) { reject(e); }
      });
    },
    deflate: function(data) {
      return new Promise(function(resolve, reject) {
        try {
          if (typeof CompressionStream === 'function') {
            var stream = new Response(new Blob([data]).stream().pipeThrough(new CompressionStream('deflate')));
            stream.arrayBuffer().then(function(ab) { resolve(new Uint8Array(ab)); }).catch(reject);
          } else {
            reject(new Error('zlib.deflate not supported in this runtime'));
          }
        } catch (e) { reject(e); }
      });
    },
  };

  console.log('[lx_bridge] loaded');
})();
