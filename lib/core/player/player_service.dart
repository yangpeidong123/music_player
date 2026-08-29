import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../engine/source_engine.dart';
import 'lyrics_engine.dart';

/// 播放模式
enum PlayMode {
  sequence,    // 顺序播放
  loop,         // 列表循环
  singleLoop,   // 单曲循环
  random,       // 随机播放

  get label => switch (this) {
    PlayMode.sequence => '顺序播放',
    PlayMode.loop => '列表循环',
    PlayMode.singleLoop => '单曲循环',
    PlayMode.random => '随机播放',
  };

  get nextMode => switch (this) {
    PlayMode.sequence => PlayMode.loop,
    PlayMode.loop => PlayMode.singleLoop,
    PlayMode.singleLoop => PlayMode.random,
    PlayMode.random => PlayMode.sequence,
  };
}

/// 播放状态数据
@immutable
class PlayerStateData {
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final Duration bufferedPosition;
  final ProcessingState processingState;
  final MusicInfo? currentMusic;
  final int currentIndex;
  final List<MusicInfo> queue;
  final PlayMode playMode;
  final String quality;
  final int currentLyricIndex;
  final String? errorMessage;

  const PlayerStateData({
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.bufferedPosition = Duration.zero,
    this.processingState = ProcessingState.idle,
    this.currentMusic,
    this.currentIndex = -1,
    this.queue = const [],
    this.playMode = PlayMode.sequence,
    this.quality = '128k',
    this.currentLyricIndex = -1,
    this.errorMessage,
  });

  bool get hasError => errorMessage != null;
  bool get hasNext => currentIndex < queue.length - 1;
  bool get hasPrevious => currentIndex > 0;

  PlayerStateData copyWith({
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    Duration? bufferedPosition,
    ProcessingState? processingState,
    MusicInfo? currentMusic,
    int? currentIndex,
    List<MusicInfo>? queue,
    PlayMode? playMode,
    String? quality,
    int? currentLyricIndex,
    String? errorMessage,
    bool clearError = false,
  }) {
    return PlayerStateData(
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      bufferedPosition: bufferedPosition ?? this.bufferedPosition,
      processingState: processingState ?? this.processingState,
      currentMusic: currentMusic ?? this.currentMusic,
      currentIndex: currentIndex ?? this.currentIndex,
      queue: queue ?? this.queue,
      playMode: playMode ?? this.playMode,
      quality: quality ?? this.quality,
      currentLyricIndex: currentLyricIndex ?? this.currentLyricIndex,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
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
  String _currentQuality = '128k';
  String? _lastError;

  // 重试机制
  int _retryCount = 0;
  static const int _maxRetries = 3;

  // 定时关闭
  bool _sleepTimerActive = false;
  Timer? _sleepTimer;
  DateTime? _sleepTimerEnd;

  // 状态流
  final _stateController = StreamController<PlayerStateData>.broadcast();
  Stream<PlayerStateData> get stateStream => _stateController.stream;
  Stream<LyricState> get lyricsStream => _lyricsEngine.stateStream;
  LyricsEngine get lyricsEngine => _lyricsEngine;

  PlayerStateData get currentState => PlayerStateData(
        isPlaying: _player.playing,
        position: _player.position,
        duration: _player.duration ?? Duration.zero,
        bufferedPosition: _player.bufferedPosition,
        processingState: _player.processingState,
        currentMusic: _currentMusic,
        currentIndex: _currentIndex,
        queue: _queue,
        playMode: _playMode,
        quality: _currentQuality,
        currentLyricIndex: _lyricsEngine.state.currentIndex,
        errorMessage: _lastError,
      );

  PlayerService({SourceEngine? sourceEngine}) : _sourceEngine = sourceEngine {
    _setupListeners();
  }

  void _setupListeners() {
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

  void _emit() {
    if (!_stateController.isClosed) {
      _stateController.add(currentState);
    }
  }

  void _setError(String? message) {
    _lastError = message;
    if (message != null) debugPrint('[Player] 错误: $message');
    _emit();
  }

  // ============================================================
  // 队列管理
  // ============================================================

  void setQueue(List<MusicInfo> queue, {int startIndex = 0}) {
    if (queue.isEmpty) {
      clearQueue();
      return;
    }
    _queue = List.from(queue);
    _currentIndex = startIndex.clamp(0, queue.length - 1);
    _playAt(_currentIndex);
  }

  void addToQueue(MusicInfo m) {
    _queue.add(m);
    _emit();
  }

  void insertNext(MusicInfo m) {
    if (_currentIndex < _queue.length - 1) {
      _queue.insert(_currentIndex + 1, m);
    } else {
      _queue.add(m);
    }
    _emit();
  }

  void removeFromQueue(int index) {
    if (index < 0 || index >= _queue.length) return;
    if (index < _currentIndex) {
      _currentIndex--;
    } else if (index == _currentIndex) {
      _player.stop();
    }
    _queue.removeAt(index);
    _emit();
  }

  void clearQueue() {
    _queue.clear();
    _currentIndex = -1;
    _player.stop();
    _currentMusic = null;
    _lyricsEngine.clear();
    _setError(null);
    _emit();
  }

  // ============================================================
  // 播放控制
  // ============================================================

  Future<void> _playAt(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _currentIndex = index;
    _currentMusic = _queue[index];
    _setError(null);
    _retryCount = 0;
    _emit();

    if (_sourceEngine == null || _currentMusic == null) return;

    try {
      final url = await _sourceEngine!.getMusicUrl(
        source: _currentMusic!.source,
        music: _currentMusic!,
        quality: _currentQuality,
      );
      if (url == null || url.isEmpty) {
        _setError('无法获取播放链接');
        _tryNext();
        return;
      }
      await _player.setUrl(url);
      await _player.play();
      // 异步加载歌词
      _loadLyrics();
    } on Exception catch (e) {
      _setError('加载失败: $e');
      _tryNext();
    }
  }

  Future<void> _loadLyrics() async {
    if (_sourceEngine == null || _currentMusic == null) return;
    try {
      final lrc = await _sourceEngine!.getMusicLyric(
        source: _currentMusic!.source,
        music: _currentMusic!,
      );
      if (lrc != null && lrc.isNotEmpty) {
        _lyricsEngine.loadLyrics(lrc);
      } else {
        _lyricsEngine.clear();
      }
    } catch (_) {
      _lyricsEngine.clear();
    }
  }

  Future<void> playOrPause() async {
    if (_player.playing) {
      await _player.pause();
    } else if (_currentIndex >= 0) {
      await _player.play();
    } else if (_queue.isNotEmpty) {
      await _playAt(0);
    }
    _emit();
  }

  Future<void> next() async {
    if (_queue.isEmpty) return;
    int nextIndex;
    if (_playMode == PlayMode.random) {
      nextIndex = _randomIndex();
    } else {
      nextIndex = _currentIndex + 1;
      if (nextIndex >= _queue.length) nextIndex = 0;
    }
    await _playAt(nextIndex);
  }

  Future<void> previous() async {
    if (_queue.isEmpty) return;
    // 超过 3 秒回到当前歌曲开头
    if (_player.position.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }
    int prevIndex = _currentIndex - 1;
    if (prevIndex < 0) prevIndex = _queue.length - 1;
    await _playAt(prevIndex);
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
    _lyricsEngine.updatePosition(position);
    _emit();
  }

  void setPlayMode(PlayMode mode) {
    _playMode = mode;
    _emit();
  }

  void cyclePlayMode() {
    setPlayMode(_playMode.nextMode);
  }

  void setQuality(String quality) {
    if (_currentQuality == quality) return;
    _currentQuality = quality;
    if (_currentMusic != null) {
      _playAt(_currentIndex);
    }
    _emit();
  }

  /// 自动失败时跳到下一首
  void _tryNext() {
    if (_retryCount < _maxRetries && _currentIndex < _queue.length - 1) {
      _retryCount++;
      next();
    } else if (_queue.length > 1 && _currentIndex < _queue.length - 1) {
      next();
    }
  }

  // ============================================================
  // 定时关闭
  // ============================================================

  void startSleepTimer(Duration d) {
    _sleepTimer?.cancel();
    _sleepTimerActive = true;
    _sleepTimerEnd = DateTime.now().add(d);
    _sleepTimer = Timer(d, () {
      _player.pause();
      _sleepTimerActive = false;
      _sleepTimerEnd = null;
      _emit();
    });
    _emit();
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimerActive = false;
    _sleepTimerEnd = null;
    _emit();
  }

  bool get isSleepTimerActive => _sleepTimerActive;
  Duration? get sleepTimerRemaining {
    if (_sleepTimerEnd == null) return null;
    final remaining = _sleepTimerEnd!.difference(DateTime.now());
    return remaining.isNegative ? null : remaining;
  }

  // ============================================================
  // 播放完成
  // ============================================================

  void _onSongComplete() {
    _retryCount = 0;
    switch (_playMode) {
      case PlayMode.singleLoop:
        _playAt(_currentIndex);
        break;
      case PlayMode.sequence:
        if (_currentIndex < _queue.length - 1) {
          next();
        } else {
          _player.stop();
          _setError(null);
          _emit();
        }
        break;
      case PlayMode.loop:
        next();
        break;
      case PlayMode.random:
        next();
        break;
    }
  }

  int _randomIndex() {
    if (_queue.length <= 1) return 0;
    final random = DateTime.now().microsecondsSinceEpoch;
    int r;
    do {
      r = random % _queue.length;
    } while (r == _currentIndex);
    return r;
  }

  void dispose() {
    _sleepTimer?.cancel();
    _player.dispose();
    _lyricsEngine.dispose();
    _stateController.close();
  }
}
