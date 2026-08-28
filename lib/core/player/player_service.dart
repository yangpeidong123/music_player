import 'dart:async';
import 'package:just_audio/just_audio.dart';
import '../engine/source_engine.dart';
import 'lyrics_engine.dart';

/// 播放模式
enum PlayMode { sequence, loop, singleLoop, random }

/// 播放状态数据
class PlayerStateData {
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final MusicInfo? currentMusic;
  final int currentIndex;
  final List<MusicInfo> queue;
  final PlayMode playMode;
  final int currentLyricIndex;

  const PlayerStateData({
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.currentMusic,
    this.currentIndex = -1,
    this.queue = const [],
    this.playMode = PlayMode.sequence,
    this.currentLyricIndex = -1,
  });

  PlayerStateData copyWith({
    bool? isPlaying, Duration? position, Duration? duration,
    MusicInfo? currentMusic, int? currentIndex, List<MusicInfo>? queue,
    PlayMode? playMode, int? currentLyricIndex,
  }) => PlayerStateData(
    isPlaying: isPlaying ?? this.isPlaying,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    currentMusic: currentMusic ?? this.currentMusic,
    currentIndex: currentIndex ?? this.currentIndex,
    queue: queue ?? this.queue,
    playMode: playMode ?? this.playMode,
    currentLyricIndex: currentLyricIndex ?? this.currentLyricIndex,
  );
}

/// 音乐播放服务
class PlayerService {
  final AudioPlayer _player = AudioPlayer();
  final SourceEngine? _sourceEngine;
  final LyricsEngine _lyricsEngine = LyricsEngine();

  List<MusicInfo> _queue = [];
  int _currentIndex = -1;
  PlayMode _playMode = PlayMode.sequence;
  MusicInfo? _currentMusic;
  bool _sleepTimerActive = false;
  Timer? _sleepTimer;
  String _currentQuality = '128k';

  final _stateController = StreamController<PlayerStateData>.broadcast();
  Stream<PlayerStateData> get stateStream => _stateController.stream;
  Stream<LyricState> get lyricsStream => _lyricsEngine.stateStream;

  PlayerStateData get currentState => PlayerStateData(
    isPlaying: _player.playing,
    position: _player.position,
    duration: _player.duration ?? Duration.zero,
    currentMusic: _currentMusic,
    currentIndex: _currentIndex,
    queue: _queue,
    playMode: _playMode,
    currentLyricIndex: _lyricsEngine.state.currentIndex,
  );

  PlayerService({SourceEngine? sourceEngine}) : _sourceEngine = sourceEngine {
    _player.playbackEventStream.listen((_) => _emit());
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) _onSongComplete();
    });
    _player.positionStream.listen((pos) {
      _lyricsEngine.updatePosition(pos);
      _emit();
    });
    _lyricsEngine.stateStream.listen((_) => _emit());
  }

  void _emit() => _stateController.add(currentState);

  // — 队列 —
  void setQueue(List<MusicInfo> queue, {int startIndex = 0}) {
    _queue = List.from(queue);
    _currentIndex = startIndex;
    _playAt(_currentIndex);
  }
  void addToQueue(MusicInfo m) { _queue.add(m); _emit(); }
  void removeFromQueue(int i) {
    if (i < 0 || i >= _queue.length) return;
    if (i < _currentIndex) _currentIndex--;
    _queue.removeAt(i);
    _emit();
  }
  void clearQueue() {
    _queue.clear(); _currentIndex = -1;
    _player.stop(); _currentMusic = null;
    _lyricsEngine.clear(); _emit();
  }

  // — 播放 —
  Future<void> _playAt(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _currentIndex = index;
    _currentMusic = _queue[index];
    _emit();
    if (_sourceEngine != null && _currentMusic != null) {
      try {
        final url = await _sourceEngine!.getMusicUrl(
          source: _currentMusic!.source, music: _currentMusic!, quality: _currentQuality);
        if (url != null && url.isNotEmpty) {
          await _player.setUrl(url);
          await _player.play();
          _loadLyrics();
        }
      } catch (e) { print('[Player] 获取链接失败: $e'); }
    }
    _emit();
  }

  Future<void> playOrPause() async {
    if (_player.playing) { await _player.pause(); }
    else if (_currentIndex >= 0) { await _player.play(); }
    else if (_queue.isNotEmpty) { await _playAt(0); }
    _emit();
  }

  Future<void> next() async {
    if (_queue.isEmpty) return;
    int i = _playMode == PlayMode.random
      ? _randomIndex()
      : (_currentIndex + 1) % _queue.length;
    await _playAt(i);
  }

  Future<void> previous() async {
    if (_queue.isEmpty) return;
    int i = _currentIndex - 1;
    if (i < 0) i = _queue.length - 1;
    await _playAt(i);
  }

  Future<void> seek(Duration pos) async {
    await _player.seek(pos);
    _lyricsEngine.updatePosition(pos);
    _emit();
  }

  void setPlayMode(PlayMode m) { _playMode = m; _emit(); }
  void setQuality(String q) { _currentQuality = q; if (_currentMusic != null) _playAt(_currentIndex); }

  // — 定时关闭 —
  void startSleepTimer(Duration d) {
    _sleepTimer?.cancel();
    _sleepTimerActive = true;
    _sleepTimer = Timer(d, () { _player.pause(); _sleepTimerActive = false; _emit(); });
    _emit();
  }
  void cancelSleepTimer() { _sleepTimer?.cancel(); _sleepTimerActive = false; _emit(); }
  bool get isSleepTimerActive => _sleepTimerActive;

  // — 歌词 —
  Future<void> _loadLyrics() async {
    if (_sourceEngine == null || _currentMusic == null) return;
    try {
      final lrc = await _sourceEngine!.getMusicLyric(source: _currentMusic!.source, music: _currentMusic!);
      if (lrc != null && lrc.isNotEmpty) _lyricsEngine.loadLyrics(lrc);
      else _lyricsEngine.clear();
    } catch (e) { _lyricsEngine.clear(); }
  }

  void _onSongComplete() {
    switch (_playMode) {
      case PlayMode.singleLoop: _playAt(_currentIndex); break;
      case PlayMode.sequence:
        if (_currentIndex < _queue.length - 1) next();
        else _player.stop();
        break;
      default: next();
    }
  }

  int _randomIndex() {
    if (_queue.length <= 1) return 0;
    int r; do { r = DateTime.now().millisecondsSinceEpoch % _queue.length; } while (r == _currentIndex);
    return r;
  }

  void dispose() {
    _sleepTimer?.cancel();
    _player.dispose();
    _lyricsEngine.dispose();
    _stateController.close();
  }
}
