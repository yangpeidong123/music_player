import 'dart:async';

/// LRC 歌词解析器
class LyricParser {
  /// 解析 LRC 格式歌词
  /// [content] LRC 歌词文本
  /// 返回有序的歌词行列表
  static List<LyricLine> parse(String content) {
    final lines = <LyricLine>[];
    final regex = RegExp(r'\[(\d{2}):(\d{2})(?:\.(\d{1,3}))?\](.*)');

    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // 跳过元数据行 (如 [ti:xxx], [ar:xxx])
      if (trimmed.startsWith('[t') || trimmed.startsWith('[al:') || trimmed.startsWith('[by:')) {
        continue;
      }

      final matches = regex.allMatches(trimmed);
      if (matches.isEmpty) {
        // 无时间标签的歌词行（可能是纯文本）
        if (trimmed.isNotEmpty && !trimmed.startsWith('[')) {
          lines.add(LyricLine(time: Duration.zero, text: trimmed));
        }
        continue;
      }

      // 一行可能有多个时间标签 (如 [00:01.00][00:15.00]同一句歌词)
      final text = matches.last.group(4)?.trim() ?? '';
      for (final match in matches) {
        final min = int.parse(match.group(1)!);
        final sec = int.parse(match.group(2)!);
        final msStr = match.group(3) ?? '0';
        final ms = int.parse(msStr.padRight(3, '0'));
        final time = Duration(minutes: min, seconds: sec, milliseconds: ms);
        lines.add(LyricLine(time: time, text: text));
      }
    }

    // 按时间排序
    lines.sort((a, b) => a.time.compareTo(b.time));
    return lines;
  }
}

/// 歌词行
class LyricLine {
  final Duration time;
  final String text;

  LyricLine({required this.time, required this.text});

  @override
  String toString() => '[${time.toString().substring(2, 7)}]$text';
}

/// 歌词状态
class LyricState {
  final List<LyricLine> lines;
  final int currentIndex;

  const LyricState({this.lines = const [], this.currentIndex = -1});

  LyricState copyWith({List<LyricLine>? lines, int? currentIndex}) =>
      LyricState(lines: lines ?? this.lines, currentIndex: currentIndex ?? this.currentIndex);

  static const empty = LyricState();
}

/// 歌词同步引擎
///
/// 根据播放进度计算当前歌词行，支持逐行高亮。
class LyricsEngine {
  List<LyricLine> _lines = [];
  int _currentIndex = -1;
  final _controller = StreamController<LyricState>.broadcast();

  Stream<LyricState> get stateStream => _controller.stream;
  LyricState get state => LyricState(lines: _lines, currentIndex: _currentIndex);

  /// 加载歌词
  void loadLyrics(String lrcContent) {
    _lines = LyricParser.parse(lrcContent);
    _currentIndex = -1;
    _controller.add(state);
    print('[LyricsEngine] 加载 ${_lines.length} 行歌词');
  }

  /// 根据播放进度更新当前歌词行
  void updatePosition(Duration position) {
    if (_lines.isEmpty) return;

    // 找到当前时间对应的歌词行
    int newIndex = _currentIndex;
    for (int i = _lines.length - 1; i >= 0; i--) {
      if (position >= _lines[i].time) {
        newIndex = i;
        break;
      }
    }

    if (newIndex != _currentIndex) {
      _currentIndex = newIndex;
      _controller.add(state);
    }
  }

  /// 获取指定偏移的歌词行（用于预加载显示）
  LyricLine? getLine(int offset) {
    final idx = _currentIndex + offset;
    if (idx < 0 || idx >= _lines.length) return null;
    return _lines[idx];
  }

  void clear() {
    _lines = [];
    _currentIndex = -1;
    _controller.add(LyricState.empty);
  }

  void dispose() {
    _controller.close();
  }
}
