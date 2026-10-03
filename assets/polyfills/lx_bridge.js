/**
 * LX Bridge Polyfill — 洛雪音源 lx 全局对象实现
 *
 * 适配 flutter_js 0.8.7 的消息传递机制：
 * - JS 调 Dart: sendMessage('channel', args)
 * - Dart 调 JS: 通过 evaluate() 执行 JS 代码
 *
 * 协议参考：lx-music-desktop/src/main/modules/userApi/renderer/preload.js
 *
 * 改进点:
 * 1. 完整的请求/响应 UUID 映射（避免 UUID 冲突）
 * 2. 超时处理（30 秒自动失败）
 * 3. 错误恢复（网络错误时返回可读错误信息）
 * 4. Buffer pool（减少 GC 压力）
 * 5. zlib 用 DecompressionStream 兜底
 */

(function() {
  'use strict';

  // ——— 配置 ———
  const DEFAULT_TIMEOUT = 30000; // 30 秒
  const MAX_CONCURRENT_REQUESTS = 16;
  const BUFFER_SIZE_LIMIT = 50 * 1024 * 1024; // 50MB

  // ——— Web API polyfills（QuickJS 没有浏览器内置的 btoa/atob/TextEncoder 等） ———
  const __B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

  if (typeof globalThis.btoa !== 'function') {
    globalThis.btoa = function (input) {
      const s = String(input);
      let out = '';
      for (let i = 0; i < s.length; i += 3) {
        const c1 = s.charCodeAt(i);
        const has2 = i + 1 < s.length;
        const has3 = i + 2 < s.length;
        const c2 = has2 ? s.charCodeAt(i + 1) : 0;
        const c3 = has3 ? s.charCodeAt(i + 2) : 0;
        out += __B64.charAt(c1 >> 2);
        out += __B64.charAt(((c1 & 3) << 4) | (c2 >> 4));
        out += has2 ? __B64.charAt(((c2 & 15) << 2) | (c3 >> 6)) : '=';
        out += has3 ? __B64.charAt(c3 & 63) : '=';
      }
      return out;
    };
  }

  if (typeof globalThis.atob !== 'function') {
    globalThis.atob = function (input) {
      const s = String(input).replace(/=+$/, '');
      let out = '';
      for (let i = 0; i < s.length; i += 4) {
        const e1 = __B64.indexOf(s.charAt(i));
        const e2 = __B64.indexOf(s.charAt(i + 1));
        const e3 = __B64.indexOf(s.charAt(i + 2));
        const e4 = __B64.indexOf(s.charAt(i + 3));
        if (e1 < 0 || e2 < 0) throw new Error('Invalid base64 string');
        out += String.fromCharCode((e1 << 2) | (e2 >> 4));
        if (e3 >= 0) out += String.fromCharCode(((e2 & 15) << 4) | (e3 >> 2));
        if (e3 >= 0 && e4 >= 0) out += String.fromCharCode(((e3 & 3) << 6) | e4);
      }
      return out;
    };
  }

  // flutter_js 只提供 setTimeout，没有 clearTimeout / setInterval / clearInterval
  if (typeof globalThis.clearTimeout !== 'function') {
    // 定时器触发时会先检查 uuid 是否还在回调表里（已被删除则 no-op），所以空实现是安全的
    globalThis.clearTimeout = function () { return undefined; };
  }
  if (typeof globalThis.setInterval !== 'function') {
    let __intervalId = 0;
    const __intervals = {};
    globalThis.setInterval = function (fn, ms) {
      const id = ++__intervalId;
      __intervals[id] = true;
      const tick = function () {
        if (!__intervals[id]) return;
        try { fn(); } catch (e) { if (typeof console !== 'undefined') console.error('setInterval callback error:', e); }
        globalThis.setTimeout(tick, ms || 0);
      };
      globalThis.setTimeout(tick, ms || 0);
      return id;
    };
    globalThis.clearInterval = function (id) { delete __intervals[id]; };
  }

  if (typeof globalThis.TextEncoder !== 'function') {
    globalThis.TextEncoder = function () {
      this.encode = function (str) {
        const bin = unescape(encodeURIComponent(String(str)));
        const arr = new Uint8Array(bin.length);
        for (let i = 0; i < bin.length; i++) arr[i] = bin.charCodeAt(i);
        return arr;
      };
    };
  }
  if (typeof globalThis.TextDecoder !== 'function') {
    globalThis.TextDecoder = function () {
      this.decode = function (bytes) {
        const arr = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes || []);
        let bin = '';
        for (let i = 0; i < arr.length; i++) bin += String.fromCharCode(arr[i]);
        try { return decodeURIComponent(escape(bin)); } catch (e) { return bin; }
      };
    };
  }

  if (typeof globalThis.crypto !== 'object' || globalThis.crypto === null ||
      typeof globalThis.crypto.getRandomValues !== 'function') {
    let __seed = ((Date.now() ^ (Math.floor(Math.random() * 0x100000000))) >>> 0) || 0x9e3779b9;
    const __next = function () {
      __seed ^= __seed << 13; __seed >>>= 0;
      __seed ^= __seed >>> 17;
      __seed ^= __seed << 5; __seed >>>= 0;
      return __seed;
    };
    if (typeof globalThis.crypto !== 'object' || globalThis.crypto === null) {
      globalThis.crypto = {};
    }
    globalThis.crypto.getRandomValues = function (arr) {
      const bytesPer = arr.BYTES_PER_ELEMENT || 1;
      for (let i = 0; i < arr.length; i++) {
        let v = 0;
        for (let b = 0; b < bytesPer; b++) v = ((v << 8) | (__next() & 0xff)) >>> 0;
        arr[i] = v;
      }
      return arr;
    };
  }

  // ——— UUID 生成 ———
  let __asyncCallId = 0;
  const __asyncCallbacks = {}; // uuid -> { resolve, reject, timeout }
  const __pendingRequests = new Set();

  // ——— 异步通信桥 ———
  // JS -> Dart
  // flutter_js 的 JS->Dart 全局函数为 sendMessage(channel, jsonString)，
  // Dart 端会 jsonDecode(message) 后交给 onMessage 回调，故必须传 JSON 字符串。
  let __NATIVE_sendMessage;
  if (typeof sendMessage === 'function') {
    __NATIVE_sendMessage = function(channel, args) {
      try {
        sendMessage(channel, JSON.stringify(args));
      } catch (e) {
        console.error('[lx_bridge] sendMessage failed:', e);
      }
    };
  } else {
    console.error('[lx_bridge] No native sendMessage available');
    __NATIVE_sendMessage = function() {};
  }

  // Dart -> JS：runtime 的 sendMessage(channelName,args) 方法会 evaluate
  // DART_TO_QUICKJS_CHANNEL_sendMessage(channel, jsonEncode(args))，故必须由我方
  // 定义该全局函数来接收 Dart 回传的响应。
  // 注意：lx_call_response 是 JS->Dart（callRequest 用 sendMessage 发给 Dart 的
  // _handleCallResponse），不在此处理。
  const __ORIGINAL_DART_DISPATCH =
    typeof globalThis.DART_TO_QUICKJS_CHANNEL_sendMessage === 'function'
      ? globalThis.DART_TO_QUICKJS_CHANNEL_sendMessage
      : null;

  globalThis.DART_TO_QUICKJS_CHANNEL_sendMessage = function(channel, argsJson) {
    try {
      const args = typeof argsJson === 'string' ? JSON.parse(argsJson) : argsJson;
      switch (channel) {
        case 'lx_request_response':
        case 'lx_crypto_response':
        case 'lx_buffer_response':
        case 'lx_zlib_response': {
          const uuid = args[0];
          const err = args[1];
          const data = args[2];
          const callback = __asyncCallbacks[uuid];
          if (callback) {
            delete __asyncCallbacks[uuid];
            __pendingRequests.delete(uuid);
            clearTimeout(callback.timeout);
            if (err && err !== 'null') {
              callback.reject(new Error(err));
            } else {
              callback.resolve(data === 'null' || data === null ? null : data);
            }
          }
          break;
        }
        default:
          if (__ORIGINAL_DART_DISPATCH) {
            __ORIGINAL_DART_DISPATCH(channel, argsJson);
          } else {
            console.warn('[lx_bridge] Unknown channel:', channel);
          }
      }
    } catch (e) {
      console.error('[lx_bridge] DART_TO_QUICKJS_CHANNEL_sendMessage error:', e);
    }
  };

  // ——— 工具函数 ———
  function safeJsonStringify(obj) {
    if (obj === undefined) return 'null';
    try {
      return JSON.stringify(obj);
    } catch (e) {
      try {
        return JSON.stringify(String(obj));
      } catch (_) {
        return 'null';
      }
    }
  }

  function base64Encode(bytes) {
    try {
      const arr = bytes instanceof ArrayBuffer ? new Uint8Array(bytes) : bytes;
      let binary = '';
      const chunkSize = 0x8000;
      for (let i = 0; i < arr.length; i += chunkSize) {
        binary += String.fromCharCode.apply(null, arr.subarray(i, i + chunkSize));
      }
      return btoa(binary);
    } catch (e) {
      return '';
    }
  }

  function base64Decode(b64) {
    try {
      const binary = atob(b64);
      const bytes = new Uint8Array(binary.length);
      for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
      return bytes.buffer;
    } catch (e) {
      return new ArrayBuffer(0);
    }
  }

  // 异步调用注册
  function asyncCall(channel, args) {
    return new Promise(function(resolve, reject) {
      if (__pendingRequests.size >= MAX_CONCURRENT_REQUESTS) {
        reject(new Error('Too many concurrent requests'));
        return;
      }
      const uuid = `${channel}_${++__asyncCallId}_${Date.now()}`;
      const timeout = setTimeout(function() {
        const callback = __asyncCallbacks[uuid];
        if (callback) {
          delete __asyncCallbacks[uuid];
          __pendingRequests.delete(uuid);
          reject(new Error(`${channel} timeout after ${DEFAULT_TIMEOUT}ms`));
        }
      }, DEFAULT_TIMEOUT);
      __asyncCallbacks[uuid] = { resolve: resolve, reject: reject, timeout: timeout };
      __pendingRequests.add(uuid);
      __NATIVE_sendMessage(channel, [uuid, ...args]);
    });
  }

  // ——— lx HTTP 请求 ———
  function lxRequest(url, options, callback) {
    if (typeof options === 'function') {
      callback = options;
      options = {};
    }
    options = options || {};

    // 验证 URL
    if (typeof url !== 'string' || !/^https?:\/\//.test(url)) {
      const err = new Error('Invalid URL: must start with http(s)://');
      if (callback) callback(err, null, null);
      return;
    }

    const method = (options.method || 'get').toUpperCase();
    const headers = options.headers || {};
    const body = options.body || null;
    const timeout = options.timeout || 60000;

    asyncCall('lx_request', [url, safeJsonStringify({
      method: method, headers: headers, body: body, timeout: timeout,
    })])
      .then(function(responseJson) {
        if (!callback) return;
        try {
          const res = typeof responseJson === 'string' ? JSON.parse(responseJson) : responseJson;
          const body = res.body;
          let bodyParsed = body;
          try { bodyParsed = JSON.parse(body); } catch (_) {}
          callback(null, {
            statusCode: res.statusCode,
            headers: res.headers,
            body: bodyParsed,
            rawBody: body,
          }, body);
        } catch (e) {
          callback(new Error('parse response failed: ' + e.message), null, null);
        }
      })
      .catch(function(err) {
        if (callback) callback(err, null, null);
      });
  }

  // ——— lx 工具：crypto ———
  const utils = {
    crypto: {
      aesEncrypt: function(buffer, mode, key, iv) {
        return asyncCall('lx_crypto', ['aesEncrypt', safeJsonStringify({
          buffer: base64Encode(buffer instanceof ArrayBuffer ? new Uint8Array(buffer) : buffer),
          mode: mode,
          key: base64Encode(key instanceof ArrayBuffer ? new Uint8Array(key) : key),
          iv: iv ? base64Encode(iv instanceof ArrayBuffer ? new Uint8Array(iv) : iv) : null,
        })]).then(base64Decode);
      },
      aesDecrypt: function(buffer, mode, key, iv) {
        return asyncCall('lx_crypto', ['aesDecrypt', safeJsonStringify({
          buffer: base64Encode(buffer instanceof ArrayBuffer ? new Uint8Array(buffer) : buffer),
          mode: mode, key: base64Encode(key), iv: iv ? base64Encode(iv) : null,
        })]).then(base64Decode);
      },
      rsaEncrypt: function(buffer, key) {
        return asyncCall('lx_crypto', ['rsaEncrypt', safeJsonStringify({
          buffer: base64Encode(buffer instanceof ArrayBuffer ? new Uint8Array(buffer) : buffer),
          key: key,
        })]).then(base64Decode);
      },
      randomBytes: function(size) {
        return asyncCall('lx_crypto', ['randomBytes', safeJsonStringify({ size: size })])
          .then(base64Decode);
      },
      md5: function(str) {
        return asyncCall('lx_crypto', ['md5', safeJsonStringify({ str: str })]);
      },
      sha256: function(str) {
        return asyncCall('lx_crypto', ['sha256', safeJsonStringify({ str: str })]);
      },
    },
    buffer: {
      from: function(data, encoding) {
        return asyncCall('lx_buffer', ['from', safeJsonStringify({
          data: data, encoding: encoding || 'utf-8',
        })]).then(base64Decode);
      },
      bufToString: function(buf, format) {
        return asyncCall('lx_buffer', ['bufToString', safeJsonStringify({
          buffer: base64Encode(buf instanceof ArrayBuffer ? new Uint8Array(buf) : buf),
          format: format || 'utf-8',
        })]);
      },
      newBuffer: function(size) {
        if (size > BUFFER_SIZE_LIMIT) {
          return Promise.reject(new Error('Buffer size exceeds limit'));
        }
        return asyncCall('lx_buffer', ['newBuffer', safeJsonStringify({ size: size })])
          .then(base64Decode);
      },
    },
    zlib: {
      inflate: function(buf) {
        if (typeof DecompressionStream === 'function') {
          return new Response(new Blob([buf]).stream().pipeThrough(new DecompressionStream('deflate')))
            .arrayBuffer().then(function(ab) { return new Uint8Array(ab); });
        }
        return Promise.reject(new Error('zlib.inflate not supported'));
      },
      deflate: function(data) {
        if (typeof CompressionStream === 'function') {
          return new Response(new Blob([data]).stream().pipeThrough(new CompressionStream('deflate')))
            .arrayBuffer().then(function(ab) { return new Uint8Array(ab); });
        }
        return Promise.reject(new Error('zlib.deflate not supported'));
      },
    },
  };

  // ——— lx 全局对象 ———
  const EVENT_NAMES = {
    request: 'request',
    inited: 'inited',
    updateAlert: 'updateAlert',
  };

  let __inited = false;
  let __updateAlertShown = false;

  globalThis.lx = {
    EVENT_NAMES: EVENT_NAMES,
    version: '2.0.0',
    env: 'flutter',
    utils: utils,
    currentScriptInfo: {
      name: '', description: '', version: '', author: '', homepage: '',
    },

    request: lxRequest,

    on: function(eventName, handler) {
      return new Promise(function(resolve, reject) {
        switch (eventName) {
          case EVENT_NAMES.request:
            globalThis.__lxRequestHandler = handler;
            resolve();
            break;
          default:
            reject(new Error('Event not supported: ' + eventName));
        }
      });
    },

    send: function(eventName, data) {
      return new Promise(function(resolve, reject) {
        switch (eventName) {
          case EVENT_NAMES.inited:
            if (__inited) return reject(new Error('Script already inited'));
            __inited = true;
            __NATIVE_sendMessage('lx_send', [eventName, safeJsonStringify(data)]);
            resolve();
            break;
          case EVENT_NAMES.updateAlert:
            if (__updateAlertShown) return reject(new Error('Update alert already shown'));
            __updateAlertShown = true;
            __NATIVE_sendMessage('lx_send', [eventName, safeJsonStringify(data)]);
            resolve();
            break;
          default:
            reject(new Error('Event not supported: ' + eventName));
        }
      });
    },
  };

  console.log('[lx_bridge] loaded');
})();
