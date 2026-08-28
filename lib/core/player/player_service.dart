import 'dart:async';
import 'dart:io';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:path_provider/path_provider.dart';
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
  final String? currentLyrics;
  final int currentLyricIndex;

  const PlayerStateData({
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.currentMusic,
    this.currentIndex = -1,
    this.queue = const [],
    this.playMode = PlayMode.sequence,
    this.currentLyrics,
    this.currentLyricIndex = -1,
  });

  PlayerStateData copyWith({
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    MusicInfo? currentMusic,
    int? currentIndex,
    List<MusicInfo>? queue,
    PlayMode? playMode,
    String? currentLyrics,
    int? currentLyricIndex,
  }) {
    return PlayerStateData(
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      currentMusic: currentMusic ?? this.currentMusic,
      currentIndex: currentIndex ?? this.currentIndex,
      queue: queue ?? this.queue,
      playMode: playMode ?? this.playMode,
      currentLyrics: currentLyrics ?? this.currentLyrics,
      currentLyricIndex: currentLyricIndex ?? this.currentLyricIndex,
    );
  }
}

/// 音频处理 Handler — 连接 audio_service 后台播放
class AudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer _player = AudioPlayer();
  final void Function(MediaItem?) onMediaChanged;
  final void Function(PlaybackState) onPlaybackStateChanged;

  AudioHandler({required this.onMediaChanged, required this.onPlaybackStateChanged}) {
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        // 通知完成
        onPlaybackStateChanged(playbackState.value.copyWith(
          processingState: AudioProcessingState.completed,
        ));
      }
    });
  }

  AudioPlayer get player => _player;

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setQueue(List<MediaItem> items, {int initialIndex = 0}) async {
    await _player.setAudioSource(
      ConcatenatingAudioSource(
        children: items.map((i) => AudioSource.uri(Uri.parse(i.id))).toList(),
      ),
      initialIndex: initialIndex,
    );
    queue.add(items);
  }

  Future<void> setUrl(String url) async {
    await _player.setUrl(url);
  }

  /// 转换 just_audio 事件为 audio_service PlaybackState
  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.stop,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _player.currentIndex,
    );
  }
}

/// 音乐播放服务 — 核心播放管理
///
/// 负责播放队列、后台播放、歌词同步、播放进度持久化。
class PlayerService {
  final AudioHandler? _audioHandler;
  final SourceEngine? _sourceEngine;
  final LyricsEngine _lyricsEngine = LyricsEngine();

  List<MusicInfo> _queue = [];
  int _currentIndex = -1;
  PlayMode _playMode = PlayMode.sequence;
  MusicInfo? _currentMusic;
  bool _sleepTimerActive = false;
  Timer? _sleepTimer;
  String _currentQuality = '128k';

  // 播放进度持久化
  final _lastPosition = <String, Duration>{}; // musicId -> position

  // 状态流
  final _stateController = StreamController<PlayerStateData>.broadcast();
  Stream<PlayerStateData> get stateStream => _stateController.stream;
  Stream<LyricState> get lyricsStream => _lyricsEngine.stateStream;

  AudioPlayer get _player => _audioHandler?.player ?? _fallbackPlayer;
  final AudioPlayer _fallbackPlayer = AudioPlayer();

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

  PlayerService({SourceEngine? sourceEngine, AudioHandler? audioHandler})
      : _sourceEngine = sourceEngine,
        _audioHandler = audioHandler {
    _setupListeners();
  }

  void _setupListeners() {
    // 播放事件
    _player.playbackEventStream.listen((event) {
      _emitState();
    }, onError: (error) {
      print('[Player] 播放错误: $error');
      _emitState();
    });

    // 处理状态（歌曲完成）
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        _onSongComplete();
      }
    });

    // 位置变化 → 更新歌词
    _player.positionStream.listen((position) {
      _lyricsEngine.updatePosition(position);
      _emitState();
    });

    // 歌词状态变化
    _lyricsEngine.stateStream.listen((_) => _emitState());
  }

  void _emitState() {
    _stateController.add(currentState);
  }

  // ============================================================
  // 队列管理
  // ============================================================

  /// 设置播放队列
  void setQueue(List<MusicInfo> queue, {int startIndex = 0}) {
    _queue = List.from(queue);
    _currentIndex = startIndex;
    _playAt(_currentIndex);
  }

  /// 添加到队列末尾
  void addToQueue(MusicInfo music) {
    _queue.add(music);
    _emitState();
  }

  /// 插入到下一首
  void insertNext(MusicInfo music) {
    if (_currentIndex < _queue.length - 1) {
      _queue.insert(_currentIndex + 1, music);
    } else {
      _queue.add(music);
    }
    _emitState();
  }

  /// 从队列中移除
  void removeFromQueue(int index) {
    if (index < 0 || index >= _queue.length) return;
    _queue.removeAt(index);
    if (index < _currentIndex) {
      _currentIndex--;
    } else if (index == _currentIndex) {
      _player.stop();
    }
    _emitState();
  }

  /// 清空队列
  void clearQueue() {
    _queue.clear();
    _currentIndex = -1;
    _player.stop();
    _currentMusic = null;
    _lyricsEngine.clear();
    _emitState();
  }

  // ============================================================
  // 播放控制
  // ============================================================

  /// 播放指定位置
  Future<void> _playAt(int index) async {
    if (index < 0 || index >= _queue.length) return;

    _currentIndex = index;
    _currentMusic = _queue[index];
    _emitState();

    // 从音源获取播放链接
    if (_sourceEngine != null && _currentMusic != null) {
      try {
        final url = await _sourceEngine!.getMusicUrl(
          source: _currentMusic!.source,
          music: _currentMusic!,
          quality: _currentQuality,
        );

        if (url != null && url.isNotEmpty) {
          await _player.setUrl(url);
          await _player.play();

          // 异步加载歌词和封面
          _loadLyrics();
          _loadArtwork();
        } else {
          print('[Player] 未获取到播放链接');
        }
      } catch (e) {
        print('[Player] 获取播放链接失败: $e');
      }
    }

    _emitState();
  }

  /// 播放/暂停
  Future<void> playOrPause() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      if (_currentIndex >= 0) {
        await _player.play();
      } else if (_queue.isNotEmpty) {
        await _playAt(0);
      }
    }
    _emitState();
  }

  /// 下一曲
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

  /// 上一曲
  Future<void> previous() async {
    if (_queue.isEmpty) return;
    int prevIndex = _currentIndex - 1;
    if (prevIndex < 0) prevIndex = _queue.length - 1;
    await _playAt(prevIndex);
  }

  /// 跳转进度
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    _lyricsEngine.updatePosition(position);
    _emitState();
  }

  /// 设置播放模式
  void setPlayMode(PlayMode mode) {
    _playMode = mode;
    _emitState();
  }

  /// 设置音质
  void setQuality(String quality) {
    _currentQuality = quality;
    // 如果正在播放，重新获取链接
    if (_currentMusic != null && _sourceEngine != null) {
      _playAt(_currentIndex);
    }
  }

  // ============================================================
  // 定时关闭
  // ============================================================

  /// 启动定时关闭
  void startSleepTimer(Duration duration) {
    _sleepTimer?.cancel();
    _sleepTimerActive = true;
    _sleepTimer = Timer(duration, () {
      _player.pause();
      _sleepTimerActive = false;
      _emitState();
    });
    _emitState();
  }

  /// 取消定时关闭
  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimerActive = false;
    _emitState();
  }

  bool get isSleepTimerActive => _sleepTimerActive;

  // ============================================================
  // 歌词和封面
  // ============================================================

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
    } catch (e) {
      print('[Player] 获取歌词失败: $e');
      _lyricsEngine.clear();
    }
  }

  Future<void> _loadArtwork() async {
    if (_sourceEngine == null || _currentMusic == null) return;
    if (_currentMusic!.img != null && _currentMusic!.img!.isNotEmpty) return;
    try {
      final pic = await _sourceEngine!.getMusicPic(
        source: _currentMusic!.source,
        music: _currentMusic!,
      );
      if (pic != null && pic.isNotEmpty) {
        _currentMusic = MusicInfo(
          id: _currentMusic!.id,
          name: _currentMusic!.name,
          singer: _currentMusic!.singer,
          album: _currentMusic!.album,
          source: _currentMusic!.source,
          img: pic,
          interval: _currentMusic!.interval,
          hash: _currentMusic!.hash,
        );
        _emitState();
      }
    } catch (e) {
      print('[Player] 获取封面失败: $e');
    }
  }

  // ============================================================
  // 歌曲播放完成
  // ============================================================

  void _onSongComplete() {
    switch (_playMode) {
      case PlayMode.singleLoop:
        _playAt(_currentIndex);
        break;
      case PlayMode.sequence:
        if (_currentIndex < _queue.length - 1) {
          next();
        } else {
          _player.stop();
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
    int r;
    do {
      r = DateTime.now().millisecondsSinceEpoch % _queue.length;
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
