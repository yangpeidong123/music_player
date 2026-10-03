// 本地验证 lx_bridge.js：与 Node.js 官方 crypto 交叉对比 md5 / AES / RSA / buffer / request 语义
const fs = require('fs');
const crypto = require('crypto');
const assert = require('assert');

// —— 桥接环境打桩 ——
const sent = []; // {channel, args}
globalThis.sendMessage = (channel, message) => {
  sent.push({ channel, args: JSON.parse(message) });
};

// 加载桥接（IIFE 挂到 globalThis）
const bridgeCode = fs.readFileSync(__dirname + '/../assets/polyfills/lx_bridge.js', 'utf8');
(0, eval)(bridgeCode);

const lx = globalThis.lx;
assert.ok(lx, 'lx not defined');
const toB64 = b => Buffer.from(b).toString('base64');
let pass = 0, fail = 0;
function check(name, fn) {
  try { fn(); pass++; console.log('  ok  ' + name); }
  catch (e) { fail++; console.log('FAIL  ' + name + ' :: ' + e.message); }
}

console.log('== 基础约定 ==');
check('lx.env === mobile', () => assert.strictEqual(lx.env, 'mobile'));
check('lx.version === 2.0.0', () => assert.strictEqual(lx.version, '2.0.0'));

console.log('== md5（同步 + encodeURIComponent 语义）==');
check('md5 是同步字符串', () => assert.strictEqual(typeof lx.utils.crypto.md5('abc'), 'string'));
check("md5('abc')", () =>
  assert.strictEqual(lx.utils.crypto.md5('abc'),
    crypto.createHash('md5').update(Buffer.from(encodeURIComponent('abc'))).digest('hex')));
check("md5('')", () => assert.strictEqual(lx.utils.crypto.md5(''), 'd41d8cd98f00b204e9800998ecf8427e'));
check("md5('测试 a&b=c') 对齐 encodeURIComponent", () => {
  const expect = crypto.createHash('md5').update(Buffer.from(encodeURIComponent('测试 a&b=c'))).digest('hex');
  assert.strictEqual(lx.utils.crypto.md5('测试 a&b=c'), expect);
});
check('md5 多块输入（>64 字节）对齐', () => {
  const longStr = 'The quick brown fox jumps over the lazy dog. '.repeat(7) + '端分隔符×±';
  const expect = crypto.createHash('md5').update(Buffer.from(encodeURIComponent(longStr))).digest('hex');
  assert.strictEqual(lx.utils.crypto.md5(longStr), expect);
});
check('md5 恰好 64 字节边界（无编码膨胀）', () => {
  const s = 'a'.repeat(64);
  const expect = crypto.createHash('md5').update(Buffer.from(encodeURIComponent(s))).digest('hex');
  assert.strictEqual(lx.utils.crypto.md5(s), expect);
});
check('md5 非字符串抛错', () => assert.throws(() => lx.utils.crypto.md5(123)));

console.log('== AES-128-CBC / ECB（同步）==');
const keyStr = '0123456789abcdef'; // 16 ASCII
const keyBytes = Buffer.from(keyStr, 'utf8');
const ivStr = 'fedcba9876543210';
const ivBytes = Buffer.from(ivStr, 'utf8');
const plainStr = 'Hello 洛雪音乐 1234567890';

check('aesEncrypt cbc 同步返回字节', () => {
  const out = lx.utils.crypto.aesEncrypt(plainStr, 'aes-128-cbc', keyStr, ivStr);
  assert.ok(out instanceof Uint8Array);
  const node = crypto.createCipheriv('aes-128-cbc', keyBytes, ivBytes);
  const expect = Buffer.concat([node.update(plainStr, 'utf8'), node.final()]);
  assert.strictEqual(toB64(out), expect.toString('base64'), 'cbc mismatch');
});
check('aesEncrypt ecb 对齐 node aes-128-ecb', () => {
  const out = lx.utils.crypto.aesEncrypt(plainStr, 'aes-128-ecb', keyStr, null);
  const node = crypto.createCipheriv('aes-128-ecb', keyBytes, null);
  const expect = Buffer.concat([node.update(plainStr, 'utf8'), node.final()]);
  assert.strictEqual(toB64(out), expect.toString('base64'), 'ecb mismatch');
});
check('aesEncrypt 二进制 key/iv/数据（TypedArray）', () => {
  const data = new Uint8Array([1, 2, 3, 255, 128, 0, 9]);
  const out = lx.utils.crypto.aesEncrypt(data, 'aes-128-cbc', keyBytes, ivBytes);
  const node = crypto.createCipheriv('aes-128-cbc', keyBytes, ivBytes);
  const expect = Buffer.concat([node.update(data), node.final()]);
  assert.strictEqual(toB64(out), expect.toString('base64'));
});
check('aesDecrypt cbc 回解 == 明文', () => {
  const enc = lx.utils.crypto.aesEncrypt(plainStr, 'aes-128-cbc', keyStr, ivStr);
  const dec = lx.utils.crypto.aesDecrypt(enc, 'aes-128-cbc', keyStr, ivStr);
  assert.strictEqual(Buffer.from(dec).toString('utf8'), plainStr);
});
check('aesDecrypt ecb 回解 == 明文', () => {
  const enc = lx.utils.crypto.aesEncrypt(plainStr, 'aes-128-ecb', keyStr, null);
  const dec = lx.utils.crypto.aesDecrypt(enc, 'aes-128-ecb', keyStr, null);
  assert.strictEqual(Buffer.from(dec).toString('utf8'), plainStr);
});

console.log('== randomBytes（同步）==');
check('randomBytes 返回 Uint8Array', () => {
  const b = lx.utils.crypto.randomBytes(16);
  assert.ok(b instanceof Uint8Array && b.length === 16);
});

console.log('== RSA（SPKI PEM + NoPadding）==');
const pem = fs.readFileSync(__dirname + '/test_rsa_pub.pem', 'utf8');
const keySize = 2048 / 8;
check('rsaEncrypt 对齐 node RSA_NO_PADDING', () => {
  const data = Buffer.alloc(keySize, 0);
  crypto.randomFillSync(data.subarray(0, 64)); // 前 64 字节随机，后面补 0（保证 < 模长）
  const out = lx.utils.crypto.aesEncrypt ? lx.utils.crypto.rsaEncrypt(data, pem) : null;
  assert.ok(out instanceof Uint8Array && out.length === keySize, 'out size');
  const expect = crypto.publicEncrypt({ key: pem, padding: crypto.constants.RSA_NO_PADDING }, data);
  assert.strictEqual(toB64(out), expect.toString('base64'), 'rsa mismatch');
});
check('rsaEncrypt 数据短于模长 → 左补零', () => {
  const data = Buffer.from([0x41, 0x42, 0x43]);
  const out = lx.utils.crypto.rsaEncrypt(data, pem);
  const padded = Buffer.concat([Buffer.alloc(keySize - 3, 0), data]);
  const expect = crypto.publicEncrypt({ key: pem, padding: crypto.constants.RSA_NO_PADDING }, padded);
  assert.strictEqual(toB64(out), expect.toString('base64'));
});
check('rsaEncrypt 非法 key 返回空 Uint8Array（官方行为）', () => {
  const out = lx.utils.crypto.rsaEncrypt(Buffer.from([1]), 'not-a-key');
  assert.ok(out instanceof Uint8Array && out.length === 0);
});
check('rsaEncrypt 数据超模长返回空（官方行为）', () => {
  const out = lx.utils.crypto.rsaEncrypt(Buffer.alloc(keySize + 1, 1), pem);
  assert.ok(out instanceof Uint8Array && out.length === 0);
});

console.log('== buffer（同步 + 官方语义）==');
check('buffer.from utf8', () => {
  const b = lx.utils.buffer.from('你好abc');
  assert.ok(b instanceof Uint8Array);
  assert.strictEqual(Buffer.from(b).toString('utf8'), '你好abc');
});
check('buffer.from base64', () => {
  const b = lx.utils.buffer.from('5L2g5aW9', 'base64');
  assert.strictEqual(Buffer.from(b).toString('utf8'), '你好');
});
check('buffer.from hex', () => {
  const b = lx.utils.buffer.from('48656c6c6f', 'hex');
  assert.strictEqual(Buffer.from(b).toString('utf8'), 'Hello');
});
check('buffer.bufToString hex/base64/utf8', () => {
  const b = new Uint8Array([72, 101, 108, 108, 111]);
  assert.strictEqual(lx.utils.buffer.bufToString(b, 'hex'), '48656c6c6f');
  assert.strictEqual(lx.utils.buffer.bufToString(b, 'base64'), 'SGVsbG8=');
  assert.strictEqual(lx.utils.buffer.bufToString(b, 'utf8'), 'Hello');
});

console.log('== lx.request（form/超时上限/原始 body/abort）==');
const events = [];
globalThis.sendMessage = (channel, message) => {
  events.push({ channel, args: JSON.parse(message) });
};
function dispatchResponse(uuid, payload) {
  const args = payload instanceof Error ? [uuid, payload.message, 'null']
    : [uuid, 'null', JSON.stringify(payload)];
  globalThis.DART_TO_QUICKJS_CHANNEL_sendMessage('lx_request_response', JSON.stringify(args));
}
async function checkAsync(name, fn) {
  try { await fn(); pass++; console.log('  ok  ' + name); }
  catch (e) { fail++; console.log('FAIL  ' + name + ' :: ' + e.message); }
}
const tick = () => new Promise(r => setTimeout(r, 0));

(async () => {
  await checkAsync('request 返回 abort 函数并透传 form/timeout 上限', async () => {
    events.length = 0;
    const ret = lx.request('https://example.com/api', { method: 'post', form: { a: '1', b: '中' }, timeout: 999999 }, () => {});
    assert.strictEqual(typeof ret, 'function', 'must return abort fn');
    const req = events.find(e => e.channel === 'lx_request');
    assert.ok(req, 'lx_request sent');
    const uuid = req.args[0];
    const opts = JSON.parse(req.args[2]); // args: [uuid, url, optionsJson]
    assert.strictEqual(req.args[1], 'https://example.com/api');
    assert.strictEqual(opts.method, 'POST');
    assert.strictEqual(opts.timeout, 60000, 'timeout capped at 60s');
    assert.deepStrictEqual(opts.form, { a: '1', b: '中' });
    dispatchResponse(uuid, { statusCode: 200, statusMessage: 'OK', headers: { 'content-type': 'application/json' }, body: '{"k":1}' });
  });

  await checkAsync('request 回调 body 保持原始字符串 + statusMessage', async () => {
    let got = null;
    lx.request('https://example.com/b', {}, (err, resp, body) => { got = { err, resp, body }; });
    const req = events.filter(e => e.channel === 'lx_request').pop();
    dispatchResponse(req.args[0], { statusCode: 200, statusMessage: 'OK', headers: {}, body: '{"k":1}' });
    await tick();
    assert.ok(got && !got.err, 'callback fired without error');
    assert.strictEqual(typeof got.resp.body, 'string', 'body must be string');
    assert.strictEqual(got.resp.body, '{"k":1}');
    assert.strictEqual(got.resp.statusMessage, 'OK');
    assert.strictEqual(got.body, '{"k":1}');
  });

  await checkAsync('abort 后回调不再触发，且发出 lx_request_abort', async () => {
    events.length = 0;
    let called = false;
    const abort = lx.request('https://example.com/c', {}, () => { called = true; });
    const req = events.find(e => e.channel === 'lx_request');
    abort();
    const abortMsg = events.find(e => e.channel === 'lx_request_abort');
    assert.ok(abortMsg, 'abort message sent');
    assert.strictEqual(abortMsg.args[0], req.args[0]);
    dispatchResponse(req.args[0], { statusCode: 200, headers: {}, body: 'x' });
    await tick();
    assert.strictEqual(called, false, 'callback must not fire after abort');
  });

  await checkAsync('request 错误回包 → callback(err)', async () => {
    let got = null;
    lx.request('https://example.com/e', {}, (err) => { got = err; });
    const req = events.filter(e => e.channel === 'lx_request').pop();
    dispatchResponse(req.args[0], new Error('connect timeout'));
    await tick();
    assert.ok(got instanceof Error, 'got Error');
    assert.strictEqual(got.message, 'connect timeout');
  });

  console.log('== lx.send(inited) ==');
  await checkAsync('send inited 消息格式', async () => {
    events.length = 0;
    await lx.send('inited', { sources: { kw: { type: 'music', actions: ['search'], qualitys: ['128k'] } } });
    const msg = events.find(e => e.channel === 'lx_send');
    assert.ok(msg);
    assert.strictEqual(msg.args[0], 'inited');
    const data = JSON.parse(msg.args[1]);
    assert.deepStrictEqual(data.sources.kw.qualitys, ['128k']);
  });

  console.log(`\nRESULT: ${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})().catch(e => {
  console.error('FATAL', e);
  process.exit(1);
});
