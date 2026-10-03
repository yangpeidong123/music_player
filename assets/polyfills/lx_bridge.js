/**
 * LX Bridge Polyfill — 洛雪音源 lx 全局对象实现（对齐 lx-music-mobile 官方 user-api-preload.js）
 *
 * 设计原则：与官方移动端 preload 行为逐项对齐 ——
 * 1. lx.utils.crypto / lx.utils.buffer 全部【同步】返回（官方如此，源脚本按同步使用）
 * 2. md5 = md5(encodeURIComponent(str))（官方行为，签名类接口依赖）
 * 3. AES 支持 'aes-128-cbc'（PKCS7）与 'aes-128-ecb'，密钥/IV/数据按 Base64 语义处理
 * 4. rsaEncrypt：SPKI(PUBLIC KEY) PEM + BigInt 原始模幂（RSA/ECB/NoPadding），失败返回空 Uint8Array
 * 5. lx.request：callback(err, {statusCode, statusMessage, headers, body}, body)，
 *    body 为原始字符串（不自动 JSON.parse），支持 form/formData/binary，超时上限 60s，
 *    返回 abort 函数；abort 后回调不再触发
 * 6. lx.env === 'mobile'，lx.version === '2.0.0'
 *
 * 桥接协议（flutter_js）：
 * - JS -> Dart: sendMessage(channel, JSON字符串)
 * - Dart -> JS: evaluate("DART_TO_QUICKJS_CHANNEL_sendMessage(channel, json, uuid?)")
 */

(function() {
  'use strict';

  // ——— 配置 ———
  const DEFAULT_TIMEOUT = 30000; // lx_request 异步回包兜底超时
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

  // ——— UUID / 回调表 ———
  let __asyncCallId = 0;
  const __asyncCallbacks = {}; // uuid -> { resolve, reject, timeout }
  const __pendingRequests = new Set();

  // ——— 异步通信桥 ———
  // JS -> Dart：flutter_js 的 JS->Dart 全局函数为 sendMessage(channel, jsonString)，
  // Dart 端 jsonDecode(message) 后交给 onMessage 回调，故必须传 JSON 字符串。
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

  // ——— 基础工具 ———
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
        const chunk = arr.subarray ? arr.subarray(i, i + chunkSize) : arr.slice(i, i + chunkSize);
        binary += String.fromCharCode.apply(null, chunk);
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
      return bytes; // 官方返回 Uint8Array
    } catch (e) {
      return new Uint8Array(0);
    }
  }

  // 任意输入 → Base64（对齐官方 dataToB64：string 按 UTF-8；二进制取字节）
  function toB64(input) {
    if (typeof input === 'string') return base64Encode(new TextEncoder().encode(input));
    if (input instanceof ArrayBuffer) return base64Encode(new Uint8Array(input));
    if (ArrayBuffer.isView(input)) {
      return base64Encode(new Uint8Array(input.buffer, input.byteOffset, input.byteLength));
    }
    if (Array.isArray(input)) return base64Encode(new Uint8Array(input));
    throw new Error('data type error: ' + typeof input);
  }

  function isBinaryView(input) {
    return input instanceof ArrayBuffer || ArrayBuffer.isView(input) || Array.isArray(input);
  }

  function toUint8(input) {
    if (input instanceof Uint8Array) return input;
    if (input instanceof ArrayBuffer) return new Uint8Array(input);
    if (ArrayBuffer.isView(input)) return new Uint8Array(input.buffer, input.byteOffset, input.byteLength);
    if (Array.isArray(input)) return new Uint8Array(input);
    return null;
  }

  // 字符串按 UTF-8 字节处理（对齐官方 dataToB64(string) 语义），二进制取字节
  function toBytes(input) {
    if (typeof input === 'string') return new TextEncoder().encode(input);
    return toUint8(input);
  }

  // ——— MD5（RFC1321，纯 JS 同步实现） ———
  const __MD5_K = new Uint32Array(64);
  for (let i = 0; i < 64; i++) __MD5_K[i] = Math.floor(Math.abs(Math.sin(i + 1)) * 4294967296) >>> 0;
  const __MD5_PATTERNS = [[7, 12, 17, 22], [5, 9, 14, 20], [4, 11, 16, 23], [6, 10, 15, 21]];
  const __MD5_S = new Uint32Array(64);
  for (let i = 0; i < 64; i++) __MD5_S[i] = __MD5_PATTERNS[Math.floor(i / 16)][i % 4];

  function md5Hex(str) {
    const bytes = new TextEncoder().encode(str);
    const len = bytes.length;
    const totalLen = Math.floor((len + 9 + 63) / 64) * 64;
    const buf = new Uint8Array(totalLen);
    buf.set(bytes);
    buf[len] = 0x80;
    const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
    const bitLo = (len << 3) >>> 0;
    const bitHi = Math.floor(len / 0x20000000) >>> 0; // len * 8 / 2^32
    dv.setUint32(totalLen - 8, bitLo, true);
    dv.setUint32(totalLen - 4, bitHi, true);

    let a0 = 0x67452301;
    let b0 = 0xefcdab89;
    let c0 = 0x98badcfe;
    let d0 = 0x10325476;
    const rotl = function (x, c) { return ((x << c) | (x >>> (32 - c))) >>> 0; };

    for (let off = 0; off < totalLen; off += 64) {
      const M = new Uint32Array(16);
      for (let j = 0; j < 16; j++) M[j] = dv.getUint32(off + j * 4, true);
      let A = a0, B = b0, C = c0, D = d0;
      for (let i = 0; i < 64; i++) {
        let f, g;
        if (i < 16) { f = ((B & C) | (~B & D)) >>> 0; g = i; }
        else if (i < 32) { f = ((B & D) | (C & ~D)) >>> 0; g = (5 * i + 1) % 16; }
        else if (i < 48) { f = (B ^ C ^ D) >>> 0; g = (3 * i + 5) % 16; }
        else { f = (C ^ (B | ~D)) >>> 0; g = (7 * i) % 16; }
        const tmp = D;
        D = C;
        C = B;
        const sum = (A + f + __MD5_K[i] + M[g]) >>> 0;
        B = (B + rotl(sum, __MD5_S[i])) >>> 0;
        A = tmp;
      }
      a0 = (a0 + A) >>> 0;
      b0 = (b0 + B) >>> 0;
      c0 = (c0 + C) >>> 0;
      d0 = (d0 + D) >>> 0;
    }
    const out = [a0, b0, c0, d0];
    let hex = '';
    for (let i = 0; i < 4; i++) {
      // RFC1321：每个字按小端字节序输出
      const w = out[i] >>> 0;
      for (let b = 0; b < 4; b++) {
        hex += ((w >>> (b * 8)) & 0xff).toString(16).padStart(2, '0');
      }
    }
    return hex;
  }

  // ——— AES-128（CBC/ECB + PKCS7，纯 JS 同步实现；表由 GF(2^8) 计算生成） ———
  const __GF_MUL = function (a, b) {
    let r = 0;
    for (let i = 0; i < 8; i++) {
      if (b & 1) r ^= a;
      const hi = a & 0x80;
      a = (a << 1) & 0xff;
      if (hi) a ^= 0x1b;
      b >>= 1;
    }
    return r & 0xff;
  };
  const __SBOX = new Uint8Array(256);
  const __INV_SBOX = new Uint8Array(256);
  (function initSbox() {
    for (let x = 0; x < 256; x++) {
      let inv = 0;
      if (x !== 0) {
        for (let y = 0; y < 256; y++) {
          if (__GF_MUL(x, y) === 1) { inv = y; break; }
        }
      }
      let s = inv;
      s ^= ((inv << 1) | (inv >> 7)) & 0xff;
      s ^= ((inv << 2) | (inv >> 6)) & 0xff;
      s ^= ((inv << 3) | (inv >> 5)) & 0xff;
      s ^= ((inv << 4) | (inv >> 4)) & 0xff;
      s ^= 0x63;
      __SBOX[x] = s & 0xff;
      __INV_SBOX[s & 0xff] = x;
    }
  })();
  const __RCON = [0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36];

  function __expandKey128(key) {
    const w = new Uint8Array(176);
    w.set(key.subarray(0, 16));
    for (let i = 16; i < 176; i += 4) {
      let t0 = w[i - 4], t1 = w[i - 3], t2 = w[i - 2], t3 = w[i - 1];
      if (i % 16 === 0) {
        const tmp = t0;
        t0 = __SBOX[t1] ^ __RCON[i / 16 - 1];
        t1 = __SBOX[t2];
        t2 = __SBOX[t3];
        t3 = __SBOX[tmp];
      }
      w[i] = w[i - 16] ^ t0;
      w[i + 1] = w[i - 15] ^ t1;
      w[i + 2] = w[i - 14] ^ t2;
      w[i + 3] = w[i - 13] ^ t3;
    }
    return w;
  }

  function __subBytes(s) { for (let i = 0; i < 16; i++) s[i] = __SBOX[s[i]]; }
  function __invSubBytes(s) { for (let i = 0; i < 16; i++) s[i] = __INV_SBOX[s[i]]; }
  function __shiftRows(s) {
    let t = s[1]; s[1] = s[5]; s[5] = s[9]; s[9] = s[13]; s[13] = t;
    t = s[2]; s[2] = s[10]; s[10] = t; t = s[6]; s[6] = s[14]; s[14] = t;
    t = s[15]; s[15] = s[11]; s[11] = s[7]; s[7] = s[3]; s[3] = t;
  }
  function __invShiftRows(s) {
    let t = s[13]; s[13] = s[9]; s[9] = s[5]; s[5] = s[1]; s[1] = t;
    t = s[2]; s[2] = s[10]; s[10] = t; t = s[6]; s[6] = s[14]; s[14] = t;
    t = s[3]; s[3] = s[7]; s[7] = s[11]; s[11] = s[15]; s[15] = t;
  }
  function __mixColumns(s) {
    for (let c = 0; c < 4; c++) {
      const i = c * 4;
      const a0 = s[i], a1 = s[i + 1], a2 = s[i + 2], a3 = s[i + 3];
      const t = a0 ^ a1 ^ a2 ^ a3;
      s[i] ^= t ^ __GF_MUL(a0 ^ a1, 2);
      s[i + 1] ^= t ^ __GF_MUL(a1 ^ a2, 2);
      s[i + 2] ^= t ^ __GF_MUL(a2 ^ a3, 2);
      s[i + 3] ^= t ^ __GF_MUL(a3 ^ a0, 2);
    }
  }
  function __invMixColumns(s) {
    for (let c = 0; c < 4; c++) {
      const i = c * 4;
      const a0 = s[i], a1 = s[i + 1], a2 = s[i + 2], a3 = s[i + 3];
      s[i] = __GF_MUL(a0, 14) ^ __GF_MUL(a1, 11) ^ __GF_MUL(a2, 13) ^ __GF_MUL(a3, 9);
      s[i + 1] = __GF_MUL(a0, 9) ^ __GF_MUL(a1, 14) ^ __GF_MUL(a2, 11) ^ __GF_MUL(a3, 13);
      s[i + 2] = __GF_MUL(a0, 13) ^ __GF_MUL(a1, 9) ^ __GF_MUL(a2, 14) ^ __GF_MUL(a3, 11);
      s[i + 3] = __GF_MUL(a0, 11) ^ __GF_MUL(a1, 13) ^ __GF_MUL(a2, 9) ^ __GF_MUL(a3, 14);
    }
  }
  function __addRoundKey(s, w, round) {
    for (let i = 0; i < 16; i++) s[i] ^= w[round * 16 + i];
  }
  // 状态布局：s[r + 4c]（列优先，标准 FIPS-197）
  function __encryptBlock(s, w) {
    __addRoundKey(s, w, 0);
    for (let round = 1; round <= 9; round++) {
      __subBytes(s);
      __shiftRows(s);
      __mixColumns(s);
      __addRoundKey(s, w, round);
    }
    __subBytes(s);
    __shiftRows(s);
    __addRoundKey(s, w, 10);
  }
  function __decryptBlock(s, w) {
    __addRoundKey(s, w, 10);
    for (let round = 9; round >= 1; round--) {
      __invShiftRows(s);
      __invSubBytes(s);
      __addRoundKey(s, w, round);
      __invMixColumns(s);
    }
    __invShiftRows(s);
    __invSubBytes(s);
    __addRoundKey(s, w, 0);
  }

  function __aesCore(data, key, iv, encrypting, chaining) {
    if (!(key instanceof Uint8Array) || key.length !== 16) {
      throw new Error('aes key must be 16 bytes');
    }
    const w = __expandKey128(key);
    let ivBytes = iv instanceof Uint8Array ? iv : new Uint8Array(16);
    if (ivBytes.length !== 16) {
      // 官方 Java：IV 截断/补零到 16 字节
      const fixed = new Uint8Array(16);
      fixed.set(ivBytes.subarray(0, Math.min(ivBytes.length, 16)));
      ivBytes = fixed;
    }
    let prev = ivBytes;
    const padLen = 16 - (data.length % 16);
    let out;
    if (encrypting) {
      out = new Uint8Array(data.length + padLen);
      out.set(data);
      for (let i = 0; i < padLen; i++) out[data.length + padLen - 1 - i] = padLen;
    } else {
      if (data.length === 0 || data.length % 16 !== 0) throw new Error('bad ciphertext length');
      out = new Uint8Array(data.length);
      out.set(data);
    }
    for (let off = 0; off < out.length; off += 16) {
      const s = new Uint8Array(16);
      if (encrypting) {
        for (let i = 0; i < 16; i++) s[i] = out[off + i] ^ (chaining ? prev[i] : 0);
        __encryptBlock(s, w);
        out.set(s, off);
        if (chaining) prev = out.subarray(off, off + 16);
      } else {
        s.set(out.subarray(off, off + 16));
        const cur = new Uint8Array(s);
        __decryptBlock(s, w);
        for (let i = 0; i < 16; i++) out[off + i] = s[i] ^ (chaining ? prev[i] : 0);
        if (chaining) prev = cur;
      }
    }
    if (!encrypting) {
      const pad = out[out.length - 1];
      if (pad < 1 || pad > 16) throw new Error('bad pkcs7 padding');
      for (let i = 0; i < pad; i++) {
        if (out[out.length - 1 - i] !== pad) throw new Error('bad pkcs7 padding');
      }
      out = out.subarray(0, out.length - pad);
      const trimmed = new Uint8Array(out.length);
      trimmed.set(out);
      return trimmed;
    }
    return out;
  }

  // ——— RSA（SPKI PEM 解析 + BigInt 模幂，对应 RSA/ECB/NoPadding） ———
  function __derReadLen(bytes, pos) {
    let len = bytes[pos.p++];
    if (len & 0x80) {
      const n = len & 0x7f;
      len = 0;
      for (let i = 0; i < n; i++) len = (len << 8) | bytes[pos.p++];
    }
    return len;
  }
  function __derReadInt(bytes, pos, end) {
    if (bytes[pos.p++] !== 0x02) throw new Error('DER: expected INTEGER');
    const len = __derReadLen(bytes, pos);
    let v = 0n;
    for (let i = 0; i < len; i++) {
      v = (v << 8n) | BigInt(bytes[pos.p++]);
    }
    if (pos.p > end) throw new Error('DER: out of range');
    return v;
  }
  function __parseSpki(der) {
    const pos = { p: 0 };
    if (der[pos.p++] !== 0x30) throw new Error('DER: expected SEQUENCE');
    __derReadLen(der, pos);
    // AlgorithmIdentifier SEQUENCE：整体跳过
    if (der[pos.p++] !== 0x30) throw new Error('DER: expected AlgorithmIdentifier');
    const algLen = __derReadLen(der, pos);
    pos.p += algLen;
    // BIT STRING
    if (der[pos.p++] !== 0x03) throw new Error('DER: expected BIT STRING');
    const bitLen = __derReadLen(der, pos);
    const unused = der[pos.p++]; // 0
    if (unused !== 0) throw new Error('DER: bad bit string');
    const innerEnd = pos.p + bitLen - 1;
    if (der[pos.p++] !== 0x30) throw new Error('DER: expected key SEQUENCE');
    __derReadLen(der, pos);
    const n = __derReadInt(der, pos, innerEnd);
    const e = __derReadInt(der, pos, innerEnd);
    if (n <= 0n || e <= 0n) throw new Error('DER: bad key');
    return { n: n, e: e };
  }
  function __bytesToBig(bytes) {
    let h = '';
    for (let i = 0; i < bytes.length; i++) h += bytes[i].toString(16).padStart(2, '0');
    return h.length ? BigInt('0x' + h) : 0n;
  }
  function __bigToBytes(x, size) {
    let h = x.toString(16);
    if (h.length % 2) h = '0' + h;
    let hex = h;
    while (hex.length < size * 2) hex = '0' + hex;
    if (hex.length > size * 2) return null; // 超出模长（官方 Java 同样失败返回空）
    const out = new Uint8Array(size);
    for (let i = 0; i < size; i++) out[i] = parseInt(hex.substr(i * 2, 2), 16);
    return out;
  }
  function __modPow(base, exp, mod) {
    let result = 1n;
    base %= mod;
    while (exp > 0n) {
      if (exp & 1n) result = (result * base) % mod;
      base = (base * base) % mod;
      exp >>= 1n;
    }
    return result;
  }

  // ——— 异步调用注册（lx_request / sha256 使用；支持 abort） ———
  function asyncCallEx(channel, args) {
    const entry = { uuid: null, promise: null };
    entry.promise = new Promise(function(resolve, reject) {
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
      __asyncCallbacks[uuid] = { resolve: resolve, reject: reject, timeout: timeout, aborted: false };
      __pendingRequests.add(uuid);
      entry.uuid = uuid; // executor 同步执行，此处赋值安全
      __NATIVE_sendMessage(channel, [uuid, ...args]);
    });
    entry.cancel = function() {
      const cb = entry.uuid != null ? __asyncCallbacks[entry.uuid] : null;
      if (!cb || cb.aborted) return false;
      cb.aborted = true; // 标记：Dart 侧回包到达时直接丢弃
      delete __asyncCallbacks[entry.uuid];
      __pendingRequests.delete(entry.uuid);
      clearTimeout(cb.timeout);
      __NATIVE_sendMessage('lx_request_abort', [entry.uuid]);
      return true;
    };
    return entry;
  }
  function asyncCall(channel, args) {
    return asyncCallEx(channel, args).promise;
  }

  // ——— lx HTTP 请求（对齐官方语义） ———
  function lxRequest(url, options, callback) {
    if (typeof options === 'function') {
      callback = options;
      options = {};
    }
    options = options || {};

    const noopAbort = function() {};
    // 验证 URL（官方交由 native 报错，这里同步报错 + 返回可调用的空 abort）
    if (typeof url !== 'string' || !/^https?:\/\//.test(url)) {
      const err = new Error('Invalid URL: must start with http(s)://');
      if (callback) callback(err, null, null);
      return noopAbort;
    }

    const method = (options.method || 'get').toUpperCase();
    const headers = options.headers || {};
    const body = options.body !== undefined ? options.body : null;
    const form = options.form !== undefined ? options.form : null;
    const formData = options.formData !== undefined ? options.formData : null;
    // 官方：timeout 上限 60s
    let timeout = 60000;
    if (options.timeout && typeof options.timeout === 'number' && options.timeout > 0) {
      timeout = Math.min(options.timeout, 60000);
    }

    const entry = asyncCallEx('lx_request', [url, safeJsonStringify({
      method: method,
      headers: headers,
      body: body,
      form: form,
      formData: formData,
      binary: options.binary === true,
      timeout: timeout,
    })]);

    entry.promise
      .then(function(responseJson) {
        if (callback) {
          const res = typeof responseJson === 'string' ? JSON.parse(responseJson) : responseJson;
          // 官方：body 原样透传（字符串），不自动 JSON.parse
          callback(null, {
            statusCode: res.statusCode,
            statusMessage: res.statusMessage,
            headers: res.headers,
            body: res.body,
            rawBody: res.body,
          }, res.body);
        }
      })
      .catch(function(err) {
        if (callback) callback(err, null, null);
      });

    // 官方：lx.request 返回 abort 函数，abort 后回调不再触发
    return function abort() {
      entry.cancel();
    };
  }

  // ——— lx 工具（官方为同步 API，这里全部同步实现） ———
  const utils = {
    crypto: {
      aesEncrypt: function(buffer, mode, key, iv) {
        const keyBytes = toBytes(key);
        if (!keyBytes) throw new Error('Invalid aes key');
        const dataBytes = toBytes(buffer);
        if (!dataBytes) throw new Error('Invalid aes buffer');
        const m = String(mode || 'aes-128-cbc').toLowerCase();
        let ivBytes;
        if (m.indexOf('ecb') >= 0) {
          ivBytes = new Uint8Array(16);
        } else {
          ivBytes = iv != null ? (toBytes(iv) || new Uint8Array(16)) : new Uint8Array(16);
        }
        return __aesCore(dataBytes, keyBytes, ivBytes, true, m.indexOf('ecb') < 0);
      },
      aesDecrypt: function(buffer, mode, key, iv) {
        const keyBytes = toBytes(key);
        if (!keyBytes) throw new Error('Invalid aes key');
        const dataBytes = toBytes(buffer);
        if (!dataBytes) throw new Error('Invalid aes buffer');
        const m = String(mode || 'aes-128-cbc').toLowerCase();
        let ivBytes;
        if (m.indexOf('ecb') >= 0) {
          ivBytes = new Uint8Array(16);
        } else {
          ivBytes = iv != null ? (toBytes(iv) || new Uint8Array(16)) : new Uint8Array(16);
        }
        return __aesCore(dataBytes, keyBytes, ivBytes, false, m.indexOf('ecb') < 0);
      },
      rsaEncrypt: function(buffer, key) {
        // 官方：key 为 PUBLIC KEY PEM（或裸 base64 DER），RSA/ECB/NoPadding；失败返回空 Uint8Array
        const empty = new Uint8Array(0);
        try {
          if (typeof key !== 'string') throw new Error('Invalid RSA key');
          let b64 = key
            .replace(/-----BEGIN PUBLIC KEY-----/g, '')
            .replace(/-----END PUBLIC KEY-----/g, '')
            .replace(/\s+/g, '');
          const der = base64Decode(b64);
          if (!der.length) throw new Error('Invalid RSA key');
          const pub = __parseSpki(der);
          const keySize = Math.ceil(__bitsOf(pub.n) / 8);
          let data = toUint8(buffer);
          if (!data) throw new Error('Invalid RSA buffer');
          if (data.length > keySize) return empty; // 官方 Java 同样失败返回空串
          const padded = new Uint8Array(keySize);
          padded.set(data, keySize - data.length);
          const m = __modPow(__bytesToBig(padded), pub.e, pub.n);
          const out = __bigToBytes(m, keySize);
          return out || empty;
        } catch (e) {
          if (typeof console !== 'undefined') console.error('[lx_bridge] rsaEncrypt error:', e);
          return empty;
        }
      },
      randomBytes: function(size) {
        // 官方实现即 Math.random（保持一致；仅用于业务随机串场景）
        const n = size | 0;
        const out = new Uint8Array(n);
        for (let i = 0; i < n; i++) out[i] = Math.floor(Math.random() * 256);
        return out;
      },
      md5: function(str) {
        // 官方：md5(encodeURIComponent(str))，同步返回 hex 字符串
        if (typeof str !== 'string') throw new Error('param required a string');
        return md5Hex(encodeURIComponent(str));
      },
      sha256: function(str) {
        // 非官方扩展能力：走 Dart 侧（异步 Promise）
        return asyncCall('lx_crypto', ['sha256', safeJsonStringify({ str: str })]);
      },
    },
    buffer: {
      from: function(input, encoding) {
        // 对齐官方：string + base64/hex/默认(utf8)；数组直接转换
        if (typeof input === 'string') {
          switch (encoding) {
            case 'binary':
              throw new Error('Binary encoding is not supported for input strings');
            case 'base64':
              return base64Decode(input);
            case 'hex': {
              const matches = input.match(/.{1,2}/g) || [];
              const bytes = new Uint8Array(matches.length);
              for (let i = 0; i < matches.length; i++) bytes[i] = parseInt(matches[i], 16) & 0xff;
              return bytes;
            }
            default:
              return new TextEncoder().encode(input);
          }
        } else if (Array.isArray(input)) {
          return new Uint8Array(input);
        } else if (input instanceof Uint8Array) {
          return input;
        } else if (input instanceof ArrayBuffer) {
          return new Uint8Array(input);
        } else if (ArrayBuffer.isView(input)) {
          return new Uint8Array(input.buffer, input.byteOffset, input.byteLength);
        }
        throw new Error('Unsupported input type: ' + (typeof input) + ' encoding: ' + encoding);
      },
      bufToString: function(buf, format) {
        const arr = toUint8(buf);
        if (!arr) throw new Error('Input is not a valid buffer: ' + buf + ' format: ' + format);
        switch (format) {
          case 'binary':
            return arr; // 官方：原样返回字节数组
          case 'hex': {
            let s = '';
            for (let i = 0; i < arr.length; i++) s += arr[i].toString(16).padStart(2, '0');
            return s;
          }
          case 'base64':
            return base64Encode(arr);
          case 'utf8':
          case 'utf-8':
          default:
            return new TextDecoder().decode(arr);
        }
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

  function __bitsOf(bigint) {
    let bits = 0;
    let v = bigint;
    while (v > 0n) {
      v >>= 1n;
      bits++;
    }
    return bits;
  }

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
    env: 'mobile', // 对齐官方（源脚本可按 env 分支）
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

  console.log('[lx_bridge] loaded (official-aligned)');
})();
