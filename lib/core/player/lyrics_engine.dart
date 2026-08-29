import 'dart:async';
import 'dart:math' as math;

/// LRC 歌词行
class LyricLine {
  final Duration time;
  final String text;
  final String? translation; // 翻译
  final String? roma; // 罗马音

  const LyricLine({
    required this.time,
    required this.text,
    this.translation,
    this.roma,
  });

  @override
  String toString() => '[${_formatTime(time)}]$text';
}

/// 格式化时间为 LRC 标签
String _formatTime(Duration d) {
  final m = d.inMinutes.toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  final ms = (d.inMilliseconds % 1000).toString().padLeft(3, '0');
  return '$m:$s.$ms';
}

/// 歌词状态
class LyricState {
  final List<LyricLine> lines;
  final int currentIndex;
  final bool loaded;

  const LyricState({
    this.lines = const [],
    this.currentIndex = -1,
    this.loaded = false,
  });

  static const empty = LyricState();

  bool get hasLyrics => lines.isNotEmpty;

  LyricLine? get currentLine => currentIndex >= 0 && currentIndex < lines.length
      ? lines[currentIndex] : null;

  LyricLine? lineAt(int offset) {
    final idx = currentIndex + offset;
    if (idx < 0 || idx >= lines.length) return null;
    return lines[idx];
  }

  LyricState copyWith({List<LyricLine>? lines, int? currentIndex, bool? loaded}) {
    return LyricState(
      lines: lines ?? this.lines,
      currentIndex: currentIndex ?? this.currentIndex,
      loaded: loaded ?? this.loaded,
    );
  }
}

/// 高级 LRC 解析器
class LyricParser {
  /// 解析 LRC 格式歌词
  /// 支持多时间标签、翻译、罗马音、元数据
  static List<LyricLine> parse(String content) {
    if (content.trim().isEmpty) return [];
    final lines = <LyricLine>[];
    final translations = <int, String>{};
    final romas = <int, String>{};

    // 正则：匹配 [时间] 或 [时间.毫秒] 和 [时间][翻译] 或 [时间.毫秒][翻译]
    final timeRegex = RegExp(r'\[(\d{1,2}):(\d{1,2})(?:\.(\d{1,3}))?\]');
    final allTimeRegex = RegExp(r'\[(\d{1,2}):(\d{1,2})(?:\.(\d{1,3}))?\]');
    final translationRegex = RegExp(r'\]\s*\[(tr|translation)\s*:[^\]]*\]', caseSensitive: false);
    final romaRegex = RegExp(r'\]\s*\[(roma|romaji)\s*:[^\]]*\]', caseSensitive: false);

    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      // 跳过元数据 [ti:xxx], [ar:xxx], [al:xxx]
      if (RegExp(r'^\[(ti|ar|al|by|offset|length)\s*:', caseSensitive: false).hasMatch(line)) {
        continue;
      }

      // 收集所有时间标签
      final matches = allTimeRegex.allMatches(line).toList();
      if (matches.isEmpty) continue;

      // 提取纯文本（去除所有时间标签）
      final text = line.replaceAll(timeRegex, '').trim();
      if (text.isEmpty) continue;

      // 提取翻译和罗马音（紧跟时间标签后）
      String? translation;
      String? roma;
      final tMatch = translationRegex.firstMatch(line);
      if (tMatch != null) {
        translation = tMatch.group(0)?.replaceAll(RegExp(r'^\]\s*\[[^\]]*\]'), '').trim();
      }
      final rMatch = romaRegex.firstMatch(line);
      if (rMatch != null) {
        roma = rMatch.group(0)?.replaceAll(RegExp(r'^\]\s*\[[^\]]*\]'), '').trim();
      }

      // 为每个时间标签创建一行
      for (final m in matches) {
        final min = int.parse(m.group(1)!);
        final sec = int.parse(m.group(2)!);
        final ms = int.parse((m.group(3) ?? '0').padRight(3, '0'));
        final time = Duration(minutes: min, seconds: sec, milliseconds: ms);
        lines.add(LyricLine(
          time: time,
          text: text,
          translation: translation,
          roma: roma,
        ));
      }
    }

    // 按时间排序
    lines.sort((a, b) => a.time.compareTo(b.time));
    return lines;
  }

  /// 解析元数据
  static Map<String, String> parseMetadata(String content) {
    final result = <String, String>{};
    final metaRegex = RegExp(r'\[(\w+)\s*:\s*([^\]]*)\]');
    for (final m in metaRegex.allMatches(content)) {
      final key = m.group(1)!.toLowerCase();
      final value = m.group(2)!.trim();
      // 跳过时间标签
      if (key.contains(':') || int.tryParse(key) != null) continue;
      result[key] = value;
    }
    return result;
  }
}

/// 歌词同步引擎
class LyricsEngine {
  List<LyricLine> _lines = [];
  int _currentIndex = -1;
  Map<String, String> _metadata = {};
  final _controller = StreamController<LyricState>.broadcast();

  Stream<LyricState> get stateStream => _controller.stream;
  LyricState get state => LyricState(
    lines: _lines,
    currentIndex: _currentIndex,
    loaded: _lines.isNotEmpty,
  );
  Map<String, String> get metadata => _metadata;

  /// 加载歌词
  void loadLyrics(String lrcContent) {
    _lines = LyricParser.parse(lrcContent);
    _metadata = LyricParser.parseMetadata(lrcContent);
    _currentIndex = -1;
    _controller.add(state);
    debugPrint('[LyricsEngine] 加载 ${_lines.length} 行歌词');
  }

  /// 清除
  void clear() {
    _lines = [];
    _metadata = {};
    _currentIndex = -1;
    _controller.add(LyricState.empty);
  }

  /// 根据播放进度更新当前歌词行 — 二分查找优化
  void updatePosition(Duration position) {
    if (_lines.isEmpty) return;
    final newIndex = _findLineIndex(position);
    if (newIndex != _currentIndex) {
      _currentIndex = newIndex;
      _controller.add(state);
    }
  }

  /// 二分查找当前歌词行
  int _findLineIndex(Duration position) {
    if (_lines.isEmpty) return -1;
    if (position < _lines.first.time) return -1;
    if (position >= _lines.last.time) {
      // 超过最后一行 - 可能进入尾奏，保持最后一行
      return _lines.length - 1;
    }

    int left = 0, right = _lines.length - 1;
    int result = -1;
    while (left <= right) {
      final mid = (left + right) ~/ 2;
      if (_lines[mid].time <= position) {
        result = mid;
        left = mid + 1;
      } else {
        right = mid - 1;
      }
    }
    return result;
  }

  /// 获取指定偏移的歌词行
  LyricLine? getLine(int offset) {
    final idx = _currentIndex + offset;
    if (idx < 0 || idx >= _lines.length) return null;
    return _lines[idx];
  }

  void dispose() {
    _controller.close();
  }
}

void debugPrint(String s) {
  // ignore: avoid_print
  print(s);
}
