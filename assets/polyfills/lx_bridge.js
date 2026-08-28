/**
 * LX Bridge Polyfill — 注入 JS 沙箱的全局 lx 对象
 * 
 * 这是对洛雪桌面端 preload.js 的 Dart 侧实现。
 * flutter_js (QuickJS) 执行此脚本后，音源脚本即可通过 globalThis.lx 通信。
 * 
 * 协议参考：lx-music-desktop/src/main/modules/userApi/renderer/preload.js
 */

;(function(globalThis) {
  'use strict';

  var EVENT_NAMES = {
    request: 'request',
    inited: 'inited',
    updateAlert: 'updateAlert',
  };

  var __requestHandler = null;
  var __inited = false;
  var __updateAlertShown = false;

  var lx = {
    EVENT_NAMES: EVENT_NAMES,
    version: '2.0.0',
    env: 'flutter',
    currentScriptInfo: null, // 由 Dart 侧设置

    // 注册事件处理器
    on: function(eventName, handler) {
      return new Promise(function(resolve, reject) {
        var validEvents = Object.values(EVENT_NAMES);
        if (validEvents.indexOf(eventName) === -1) {
          return reject(new Error('The event is not supported: ' + eventName));
        }
        switch (eventName) {
          case EVENT_NAMES.request:
            __requestHandler = handler;
            break;
          default:
            return reject(new Error('The event is not supported: ' + eventName));
        }
        resolve();
      });
    },

    // 发送事件通知
    send: function(eventName, data) {
      return new Promise(function(resolve, reject) {
        var validEvents = Object.values(EVENT_NAMES);
        if (validEvents.indexOf(eventName) === -1) {
          return reject(new Error('The event is not supported: ' + eventName));
        }
        switch (eventName) {
          case EVENT_NAMES.inited:
            if (__inited) return reject(new Error('Script is inited'));
            __inited = true;
            // 通知 Dart 侧
            __lx_native_send(eventName, JSON.stringify(data));
            resolve();
            break;
          case EVENT_NAMES.updateAlert:
            if (__updateAlertShown) return reject(new Error('Update alert already shown'));
            __updateAlertShown = true;
            __lx_native_send(eventName, JSON.stringify(data));
            resolve();
            break;
          default:
            reject(new Error('Unknown event: ' + eventName));
        }
      });
    },

    // HTTP 请求（回调模式，与洛雪桌面端一致）
    request: function(url, options, callback) {
      if (typeof options === 'function') {
        callback = options;
        options = {};
      }
      options = options || {};
      var method = options.method || 'GET';
      var headers = options.headers || {};
      var body = options.body || null;
      var timeout = options.timeout || 60000;
      var form = options.form || null;

      // 调用 Dart 侧的 HTTP 请求
      var requestId = __lx_native_request(
        JSON.stringify({
          url: url,
          method: method,
          headers: headers,
          body: body,
          form: form,
          timeout: timeout,
        })
      );

      // Dart 侧会通过 __lx_request_callback(requestId, error, response) 回调
      // 存储 callback 以便回调时找到
      __lx_callbacks[requestId] = callback;
      return requestId;
    },

    // 工具函数
    utils: {
      crypto: {
        // AES 加密/解密
        aesEncrypt: function(buffer, mode, key, iv) {
          var result = __lx_native_crypto('aesEncrypt', JSON.stringify({
            buffer: __base64_encode(buffer),
            mode: mode,
            key: __base64_encode(key),
            iv: iv ? __base64_encode(iv) : null,
          }));
          return __base64_decode(result);
        },
        aesDecrypt: function(buffer, mode, key, iv) {
          var result = __lx_native_crypto('aesDecrypt', JSON.stringify({
            buffer: __base64_encode(buffer),
            mode: mode,
            key: __base64_encode(key),
            iv: iv ? __base64_encode(iv) : null,
          }));
          return __base64_decode(result);
        },
        // RSA 加密（特殊 padding）
        rsaEncrypt: function(buffer, key) {
          var result = __lx_native_crypto('rsaEncrypt', JSON.stringify({
            buffer: __base64_encode(buffer),
            key: key,
          }));
          return __base64_decode(result);
        },
        randomBytes: function(size) {
          var result = __lx_native_crypto('randomBytes', JSON.stringify({ size: size }));
          return __base64_decode(result);
        },
        md5: function(str) {
          return __lx_native_crypto('md5', JSON.stringify({ str: str }));
        },
        sha256: function(str) {
          return __lx_native_crypto('sha256', JSON.stringify({ str: str }));
        },
      },
      buffer: {
        from: function(data, encoding) {
          if (typeof data === 'string') {
            return __base64_decode(__lx_native_buffer('from', JSON.stringify({
              data: data,
              encoding: encoding || 'utf-8',
            })));
          }
          return data; // 已经是 buffer-like
        },
        bufToString: function(buf, format) {
          return __lx_native_buffer('bufToString', JSON.stringify({
            buffer: __base64_encode(buf),
            format: format || 'utf-8',
          }));
        },
        newBuffer: function(size) {
          return __base64_decode(__lx_native_buffer('newBuffer', JSON.stringify({ size: size })));
        },
      },
      zlib: {
        inflate: function(buf) {
          return new Promise(function(resolve, reject) {
            try {
              var result = __lx_native_zlib('inflate', __base64_encode(buf));
              resolve(__base64_decode(result));
            } catch (e) {
              reject(new Error(e.message || 'inflate failed'));
            }
          });
        },
        deflate: function(data) {
          return new Promise(function(resolve, reject) {
            try {
              var result = __lx_native_zlib('deflate', __base64_encode(data));
              resolve(__base64_decode(result));
            } catch (e) {
              reject(new Error(e.message || 'deflate failed'));
            }
          });
        },
      },
    },
  };

  // Base64 编解码（Buffer 传递用）
  function __base64_encode(buf) {
    if (typeof buf === 'string') {
      return btoa(buf);
    }
    // Uint8Array 或类似
    var binary = '';
    var bytes = new Uint8Array(buf);
    for (var i = 0; i < bytes.length; i++) {
      binary += String.fromCharCode(bytes[i]);
    }
    return btoa(binary);
  }

  function __base64_decode(b64) {
    var binary = atob(b64);
    var bytes = new Uint8Array(binary.length);
    for (var i = 0; i < binary.length; i++) {
      bytes[i] = binary.charCodeAt(i);
    }
    return bytes.buffer;
  }

  // 回调存储
  var __lx_callbacks = {};

  // Dart 侧调用：HTTP 请求回调
  globalThis.__lx_request_callback = function(requestId, error, responseJson) {
    var cb = __lx_callbacks[requestId];
    if (!cb) return;
    delete __lx_callbacks[requestId];
    if (error) {
      cb(new Error(error), null, null);
    } else {
      var res = JSON.parse(responseJson);
      var body = res.body;
      var bodyParsed = body;
      try { bodyParsed = JSON.parse(body); } catch (_) {}
      cb(null, {
        statusCode: res.statusCode,
        headers: res.headers,
        body: bodyParsed,
        rawBody: body,
      }, body);
    }
  };

  // Dart 侧调用：发起 request 处理器调用
  globalThis.__lx_call_request_handler = function(requestJson) {
    var req = JSON.parse(requestJson);
    if (!__requestHandler) {
      return JSON.stringify({ error: 'No request handler registered' });
    }
    // 调用处理器（可能是 async）
    return Promise.resolve(__requestHandler(req)).then(function(result) {
      return JSON.stringify({ data: result });
    }).catch(function(err) {
      return JSON.stringify({ error: err.message || String(err) });
    });
  };

  // 暴露到全局
  globalThis.lx = lx;
  globalThis.EVENT_NAMES = EVENT_NAMES;

  // 额外的全局兼容（部分音源脚本需要）
  globalThis.setTimeout = globalThis.setTimeout || function(fn, ms) { return __lx_native_setTimeout(fn, ms); };
  globalThis.clearTimeout = globalThis.clearTimeout || function(id) { __lx_native_clearTimeout(id); };
  globalThis.console = globalThis.console || {
    log: function() { __lx_native_log('log', JSON.stringify(Array.prototype.slice.call(arguments))); },
    error: function() { __lx_native_log('error', JSON.stringify(Array.prototype.slice.call(arguments))); },
    warn: function() { __lx_native_log('warn', JSON.stringify(Array.prototype.slice.call(arguments))); },
  };

})(typeof globalThis !== 'undefined' ? globalThis : this);
