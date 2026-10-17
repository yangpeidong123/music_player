// lyrics_engine.js — Dart 端 lib/core/player/lyrics_engine.dart 的保真 JS 移植。
// 用途：在无 Flutter/Dart 工具链的环境（本仓库 CI Windows 沙箱）下真实执行
// test/lyrics_engine_test.dart 的断言逻辑，替代 `flutter test` 中的纯逻辑部分。
// 维护约定：Dart 源码逻辑变更后必须同步此文件，并保持 27 个断言全绿。

const d = (m, s, ms) => (m * 60 + s) * 1000 + (ms || 0);

class LyricLine {
  constructor(time, text, translation = null, roma = null) {
    this.time = time;
    this.text = text;
    this.translation = translation;
    this.roma = roma;
  }
}

class LyricState {
  constructor(lines = [], currentIndex = -1, loaded = false) {
    this.lines = lines;
    this.currentIndex = currentIndex;
    this.loaded = loaded;
  }
  get hasLyrics() { return this.lines.length > 0; }
  get currentLine() {
    return (this.currentIndex >= 0 && this.currentIndex < this.lines.length)
      ? this.lines[this.currentIndex] : null;
  }
  lineAt(offset) {
    const idx = this.currentIndex + offset;
    if (idx < 0 || idx >= this.lines.length) return null;
    return this.lines[idx];
  }
}

const pad2 = (n) => String(n).padStart(2, '0');
const pad3 = (n) => String(n).padStart(3, '0');

class LyricParser {
  // Dart: r'\[(\d{1,2}):(\d{1,2})(?:\.(\d{1,3}))?\]'
  static timeRegex() { return /\[(\d{1,2}):(\d{1,2})(?:\.(\d{1,3}))?\]/g; }
  // Dart: r'\[(\w+)\s*:\s*([^\]]*)\]' — NOTE: Dart \w 不含连字符
  static metaRegex() { return /\[(\w+)\s*:\s*([^\]]*)\]/g; }
  // Dart: r'\[(?:tr|translation)\s*:([^\]]*)\]'
  static trRegex() { return /\[(?:tr|translation)\s*:([^\]]*)\]/gi; }
  // Dart: r'\[(?:roma|romaji)\s*:([^\]]*)\]'
  static romaRegex() { return /\[(?:roma|romaji)\s*:([^\]]*)\]/gi; }
  // Dart: r'^\[(ti|ar|al|by|offset|length)\s*:'
  static metaLineRegex() { return /^\[(ti|ar|al|by|offset|length)\s*:/i; }

  static parse(content) {
    if (content.trim() === '') return [];
    const lines = [];

    for (const rawLine of content.split('\n')) {
      const line = rawLine.trim();
      if (line === '') continue;
      if (LyricParser.metaLineRegex().test(line)) continue;

      // Dart allMatches 语义：每次从 0 开始扫全文
      const matches = [...line.matchAll(new RegExp(LyricParser.timeRegex().source, 'g'))];
      if (matches.length === 0) continue;

      // Dart firstMatch 语义：非全局 exec 才能拿到捕获组（match(/g/) 返回全匹配数组）
      const tMatch = new RegExp(LyricParser.trRegex().source, 'i').exec(line);
      const translation = tMatch ? tMatch[1].trim() : null;
      const rMatch = new RegExp(LyricParser.romaRegex().source, 'i').exec(line);
      const roma = rMatch ? rMatch[1].trim() : null;

      // Dart replaceAll 语义 = 全局 replace（split 会把捕获组插回结果，不能用）
      const text = line
        .replace(new RegExp(LyricParser.timeRegex().source, 'g'), '')
        .replace(new RegExp(LyricParser.trRegex().source, 'gi'), '')
        .replace(new RegExp(LyricParser.romaRegex().source, 'gi'), '')
        .trim();
      if (text === '') continue;

      for (const m of matches) {
        const min = parseInt(m[1], 10);
        const sec = parseInt(m[2], 10);
        const ms = parseInt((m[3] || '0').padEnd(3, '0'), 10);
        lines.push(new LyricLine(
          d(min, sec, ms),
          text,
          (translation == null || translation === '') ? null : translation,
          (roma == null || roma === '') ? null : roma,
        ));
      }
    }
    lines.sort((a, b) => a.time - b.time || 0);
    return lines;
  }

  static parseMetadata(content) {
    const result = {};
    const metaRegex = LyricParser.metaRegex();
    let m;
    while ((m = metaRegex.exec(content)) !== null) {
      const key = m[1].toLowerCase();
      const value = m[2].trim();
      if (key.includes(':') || (Number.isInteger(parseInt(key, 10)) && /^\d+$/.test(key))) continue;
      result[key] = value;
    }
    return result;
  }
}

class LyricsEngine {
  constructor() {
    this._lines = [];
    this._currentIndex = -1;
    this._metadata = {};
  }

  get state() {
    return new LyricState(this._lines, this._currentIndex, this._lines.length > 0);
  }
  get metadata() { return this._metadata; }

  loadLyrics(lrc) {
    this._lines = LyricParser.parse(lrc);
    this._metadata = LyricParser.parseMetadata(lrc);
    this._currentIndex = -1;
  }

  clear() {
    this._lines = [];
    this._metadata = {};
    this._currentIndex = -1;
  }

  updatePosition(position) {
    if (this._lines.length === 0) return;
    const newIndex = this._findLineIndex(position);
    if (newIndex !== this._currentIndex) this._currentIndex = newIndex;
  }

  _findLineIndex(position) {
    if (this._lines.length === 0) return -1;
    if (position < this._lines[0].time) return -1;
    if (position >= this._lines[this._lines.length - 1].time) {
      return this._lines.length - 1;
    }
    let left = 0, right = this._lines.length - 1, result = -1;
    while (left <= right) {
      const mid = (left + right) >>> 1;
      if (this._lines[mid].time <= position) {
        result = mid;
        left = mid + 1;
      } else {
        right = mid - 1;
      }
    }
    return result;
  }

  getLine(offset) {
    const idx = this._currentIndex + offset;
    if (idx < 0 || idx >= this._lines.length) return null;
    return this._lines[idx];
  }
}

module.exports = { LyricLine, LyricState, LyricParser, LyricsEngine, d };
