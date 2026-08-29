import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/core/player/lyrics_engine.dart';

void main() {
  group('LyricParser', () {
    test('parses simple LRC format', () {
      const lrc = '''
[00:00.00] 歌曲开始
[00:05.50] 第一句歌词
[00:10.00] 第二句歌词
[00:15.25] 第三句歌词
''';
      final lines = LyricParser.parse(lrc);
      expect(lines, hasLength(4));
      expect(lines[0].time, const Duration(milliseconds: 0));
      expect(lines[0].text, '歌曲开始');
      expect(lines[1].time, const Duration(milliseconds: 5500));
      expect(lines[1].text, '第一句歌词');
      expect(lines[3].time, const Duration(milliseconds: 15250));
    });

    test('handles empty input', () {
      expect(LyricParser.parse(''), isEmpty);
      expect(LyricParser.parse('   \n  \n'), isEmpty);
    });

    test('skips metadata lines', () {
      const lrc = '''
[ti:测试歌曲]
[ar:测试歌手]
[al:测试专辑]
[00:00.00] 实际歌词
[00:05.00] 更多歌词
''';
      final lines = LyricParser.parse(lrc);
      expect(lines, hasLength(2));
      expect(lines[0].text, '实际歌词');
      expect(lines[1].text, '更多歌词');
    });

    test('handles multiple time tags on one line', () {
      const lrc = '[00:00.00][01:00.00] 同时唱的歌词';
      final lines = LyricParser.parse(lrc);
      expect(lines, hasLength(2));
      expect(lines[0].time, const Duration(seconds: 0));
      expect(lines[1].time, const Duration(minutes: 1));
      expect(lines[0].text, '同时唱的歌词');
      expect(lines[1].text, '同时唱的歌词');
    });

    test('sorts out-of-order lines', () {
      const lrc = '''
[00:10.00] 后面的
[00:00.00] 前面的
[00:05.00] 中间的
''';
      final lines = LyricParser.parse(lrc);
      expect(lines[0].text, '前面的');
      expect(lines[1].text, '中间的');
      expect(lines[2].text, '后面的');
    });

    test('parses metadata', () {
      const lrc = '''
[ti:歌曲名]
[ar:艺术家]
[al:专辑名]
[by:编辑者]
[00:00.00] 歌词
''';
      final meta = LyricParser.parseMetadata(lrc);
      expect(meta['ti'], '歌曲名');
      expect(meta['ar'], '艺术家');
      expect(meta['al'], '专辑名');
    });

    test('parses translation tag', () {
      const lrc = '[00:05.00] 原文歌词 [tr:翻译歌词]';
      final lines = LyricParser.parse(lrc);
      expect(lines, hasLength(1));
      expect(lines[0].text, '原文歌词');
      expect(lines[0].translation, '翻译歌词');
      expect(lines[0].roma, isNull);
    });

    test('parses roma tag', () {
      const lrc = '[00:05.00] 原文歌词 [roma:romaji]';
      final lines = LyricParser.parse(lrc);
      expect(lines, hasLength(1));
      expect(lines[0].text, '原文歌词');
      expect(lines[0].roma, 'romaji');
    });

    test('parses translation and roma together', () {
      const lrc = '[00:05.00] 原文 [tr:翻译] [roma:罗马音]';
      final lines = LyricParser.parse(lrc);
      expect(lines, hasLength(1));
      expect(lines[0].text, '原文');
      expect(lines[0].translation, '翻译');
      expect(lines[0].roma, '罗马音');
    });

    test('translation does not leak into text', () {
      const lrc = '[00:00.00] 第一句 [tr:first]\n[00:05.00] 第二句';
      final lines = LyricParser.parse(lrc);
      expect(lines[0].text, '第一句');
      expect(lines[0].translation, 'first');
      expect(lines[1].text, '第二句');
      expect(lines[1].translation, isNull);
    });
  });

  group('LyricsEngine', () {
    late LyricsEngine engine;

    setUp(() {
      engine = LyricsEngine();
    });

    tearDown(() {
      engine.dispose();
    });

    test('initial state is empty', () {
      expect(engine.state.lines, isEmpty);
      expect(engine.state.currentIndex, -1);
      expect(engine.state.hasLyrics, isFalse);
    });

    test('loadLyrics updates state', () {
      engine.loadLyrics('[00:00.00] hi\n[00:05.00] hello');
      expect(engine.state.hasLyrics, isTrue);
      expect(engine.state.lines, hasLength(2));
    });

    test('updatePosition finds correct line via binary search', () {
      engine.loadLyrics('''
[00:00.00] line0
[00:05.00] line1
[00:10.00] line2
[00:15.00] line3
''');
      engine.updatePosition(const Duration(seconds: 6));
      expect(engine.state.currentIndex, 1);
      expect(engine.state.currentLine?.text, 'line1');

      engine.updatePosition(const Duration(seconds: 12));
      expect(engine.state.currentIndex, 2);
      expect(engine.state.currentLine?.text, 'line2');
    });

    test('lineAt offset works', () {
      engine.loadLyrics('''
[00:00.00] a
[00:05.00] b
[00:10.00] c
''');
      engine.updatePosition(const Duration(seconds: 5));
      expect(engine.getLine(-1)?.text, 'a');
      expect(engine.getLine(0)?.text, 'b');
      expect(engine.getLine(1)?.text, 'c');
      expect(engine.getLine(10), isNull);
    });
  });
}
