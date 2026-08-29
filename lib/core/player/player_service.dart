import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../engine/source_engine.dart';
import 'lyrics_engine.dart';

/// 播放模式
enum PlayMode {
  sequence,    // 顺序播放
  loop,         // 列表循环
  singleLoop,   // 单曲循环
  random;       // 随机播放（注意：enum 值列表以分号结尾才能定义成员）

  String get label => switch (this) {
    PlayMode.sequence => '顺序播放',
    PlayMode.loop => '列表循环',
    PlayMode.singleLoop => '单曲循环',
    PlayMode.random => '随机播放',
  };

  PlayMode get nextMode => switch (this) {
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
  // 音源引擎改为可变、运行时注入：PlayerService 是常驻单例，
  // 切换/导入/删除音源不应导致播放器被 dispose 重建（否则播放中断、队列丢失）。
  SourceEngine? _sourceEngine;
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

  /// 运行时切换音源引擎，不影响当前播放与队列。
  void setSourceEngine(SourceEngine? engine) {
    _sourceEngine = engine;
  }

  /// 可选：播放记录回调（用于写播放历史），由 providers 层注入以避免 core 依赖 storage。
  void Function(MusicInfo music)? onPlayRecorded;

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
    final wasCurrent = index == _currentIndex;
    _queue.removeAt(index);

    if (index < _currentIndex) {
      // 删除的是当前之前的项，索引前移一位
      _currentIndex--;
      _emit();
    } else if (wasCurrent) {
      // 删除的是当前播放项：需要切到同一位置的歌（即原下一首），
      // 若没有下一首则停止。_playAt 会重新设置 _currentIndex/_currentMusic。
      if (_queue.isEmpty) {
        clearQueue();
      } else if (index < _queue.length) {
        _playAt(index);
      } else {
        // 删的是队尾，且它正在播放：停止并清除当前歌曲
        _player.stop();
        _currentIndex = -1;
        _currentMusic = null;
        _lyricsEngine.clear();
        _emit();
      }
    } else {
      // 删除的是当前之后的项，不影响当前播放
      _emit();
    }
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

    final music = _currentMusic;
    if (music == null) return;

    // 记录播放历史（本地与在线都记录）
    onPlayRecorded?.call(music);

    // 本地文件：source 为 'local'，hash 存文件路径
    if (music.source == 'local') {
      final path = music.hash;
      if (path == null || path.isEmpty) {
        _setError('本地文件路径缺失');
        return;
      }
      try {
        await _player.setFilePath(path);
        await _player.play();
        _lyricsEngine.clear();
      } on Exception catch (e) {
        _setError('本地文件加载失败: $e');
      }
      return;
    }

    // 在线：需要音源引擎
    if (_sourceEngine == null) {
      _setError('未加载音源，无法播放');
      return;
    }

    try {
      final url = await _sourceEngine!.getMusicUrl(
        source: music.source,
        music: music,
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
    // 必须在循环内取随机数；若在循环外取一次再取模，
    // 当结果恰好等于当前索引时 do-while 会永远循环（死循环）。
    final rand = math.Random();
    int r;
    do {
      r = rand.nextInt(_queue.length);
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
