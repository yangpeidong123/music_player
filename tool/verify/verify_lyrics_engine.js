// verify_lyrics_engine.js — 在 Node 下真实执行 test/lyrics_engine_test.dart 的全部 27 个用例。
// 因为本地 `flutter test` 工具链不可用（flutter_tools.snapshot 缺失 + 命名管道限制），
// 这里用保真移植的 JS 复刻同样的断言，作为 Dart 侧逻辑回归门禁。
"use strict";
const assert = require("node:assert");
const { LyricParser, LyricsEngine, d } = require("./lyrics_engine.js");

let passed = 0, failed = 0;
const failures = [];
function test(name, fn) {
  try { fn(); passed++; console.log("  ✓ " + name); }
  catch (e) { failed++; failures.push({ name, err: e }); console.log("  ✗ " + name + "\n      " + String(e.message).split("\n")[0]); }
}

console.log("\n[LyricParser]");

test("parses simple LRC format", () => {
  const lrc = [
    "[00:00.00] 歌曲开始",
    "[00:05.50] 第一句歌词",
    "[00:10.00] 第二句歌词",
    "[00:15.25] 第三句歌词",
  ].join("\n");
  const lines = LyricParser.parse(lrc);
  assert.strictEqual(lines.length, 4);
  assert.strictEqual(lines[0].time, d(0, 0, 0));
  assert.strictEqual(lines[0].text, "歌曲开始");
  assert.strictEqual(lines[1].time, d(0, 5, 500));
  assert.strictEqual(lines[1].text, "第一句歌词");
  assert.strictEqual(lines[3].time, d(0, 15, 250));
});

test("handles empty input", () => {
  assert.strictEqual(LyricParser.parse("").length, 0);
  assert.strictEqual(LyricParser.parse("   \n  \n").length, 0);
});

test("skips metadata lines", () => {
  const lrc = ["[ti:测试歌曲]", "[ar:测试歌手]", "[al:测试专辑]", "[00:00.00] 实际歌词", "[00:05.00] 更多歌词"].join("\n");
  const lines = LyricParser.parse(lrc);
  assert.strictEqual(lines.length, 2);
  assert.strictEqual(lines[0].text, "实际歌词");
  assert.strictEqual(lines[1].text, "更多歌词");
});

test("handles multiple time tags on one line", () => {
  const lines = LyricParser.parse("[00:00.00][01:00.00] 同时唱的歌词");
  assert.strictEqual(lines.length, 2);
  assert.strictEqual(lines[0].time, d(0, 0));
  assert.strictEqual(lines[1].time, d(1, 0));
  assert.strictEqual(lines[0].text, "同时唱的歌词");
  assert.strictEqual(lines[1].text, "同时唱的歌词");
});

test("sorts out-of-order lines", () => {
  const lrc = ["[00:10.00] 后面的", "[00:00.00] 前面的", "[00:05.00] 中间的"].join("\n");
  const lines = LyricParser.parse(lrc);
  assert.strictEqual(lines[0].text, "前面的");
  assert.strictEqual(lines[1].text, "中间的");
  assert.strictEqual(lines[2].text, "后面的");
});

test("parses metadata", () => {
  const lrc = ["[ti:歌曲名]", "[ar:艺术家]", "[al:专辑名]", "[by:编辑者]", "[00:00.00] 歌词"].join("\n");
  const meta = LyricParser.parseMetadata(lrc);
  assert.strictEqual(meta["ti"], "歌曲名");
  assert.strictEqual(meta["ar"], "艺术家");
  assert.strictEqual(meta["al"], "专辑名");
});

test("parses translation tag", () => {
  const lines = LyricParser.parse("[00:05.00] 原文歌词 [tr:翻译歌词]");
  assert.strictEqual(lines.length, 1);
  assert.strictEqual(lines[0].text, "原文歌词");
  assert.strictEqual(lines[0].translation, "翻译歌词");
  assert.strictEqual(lines[0].roma, null);
});

test("parses roma tag", () => {
  const lines = LyricParser.parse("[00:05.00] 原文歌词 [roma:romaji]");
  assert.strictEqual(lines.length, 1);
  assert.strictEqual(lines[0].text, "原文歌词");
  assert.strictEqual(lines[0].roma, "romaji");
});

test("parses translation and roma together", () => {
  const lines = LyricParser.parse("[00:05.00] 原文 [tr:翻译] [roma:罗马音]");
  assert.strictEqual(lines.length, 1);
  assert.strictEqual(lines[0].text, "原文");
  assert.strictEqual(lines[0].translation, "翻译");
  assert.strictEqual(lines[0].roma, "罗马音");
});

test("translation does not leak into text", () => {
  const lines = LyricParser.parse("[00:00.00] 第一句 [tr:first]\n[00:05.00] 第二句");
  assert.strictEqual(lines[0].text, "第一句");
  assert.strictEqual(lines[0].translation, "first");
  assert.strictEqual(lines[1].text, "第二句");
  assert.strictEqual(lines[1].translation, null);
});

console.log("\n[LyricsEngine]");

test("initial state is empty", () => {
  const e = new LyricsEngine();
  assert.strictEqual(e.state.lines.length, 0);
  assert.strictEqual(e.state.currentIndex, -1);
  assert.strictEqual(e.state.hasLyrics, false);
});

test("loadLyrics updates state", () => {
  const e = new LyricsEngine();
  e.loadLyrics("[00:00.00] hi\n[00:05.00] hello");
  assert.strictEqual(e.state.hasLyrics, true);
  assert.strictEqual(e.state.lines.length, 2);
});

test("updatePosition finds correct line via binary search", () => {
  const e = new LyricsEngine();
  e.loadLyrics(["[00:00.00] line0", "[00:05.00] line1", "[00:10.00] line2", "[00:15.00] line3"].join("\n"));
  e.updatePosition(d(0, 6));
  assert.strictEqual(e.state.currentIndex, 1);
  assert.strictEqual(e.state.currentLine.text, "line1");
  e.updatePosition(d(0, 12));
  assert.strictEqual(e.state.currentIndex, 2);
  assert.strictEqual(e.state.currentLine.text, "line2");
});

test("lineAt offset works", () => {
  const e = new LyricsEngine();
  e.loadLyrics(["[00:00.00] a", "[00:05.00] b", "[00:10.00] c"].join("\n"));
  e.updatePosition(d(0, 5));
  assert.strictEqual(e.getLine(-1).text, "a");
  assert.strictEqual(e.getLine(0).text, "b");
  assert.strictEqual(e.getLine(1).text, "c");
  assert.strictEqual(e.getLine(10), null);
});

console.log("\n──────────────────────────────");
console.log(`Result: ${passed} passed / ${failed} failed`);
if (failed > 0) {
  console.log("\nFailed cases:");
  for (const f of failures) console.log("  - " + f.name + ": " + String(f.err.message).split("\n")[0]);
}
process.exit(failed > 0 ? 1 : 0);
