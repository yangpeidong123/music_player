import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/engine/source_engine.dart';
import '../../core/engine/source_manager.dart';
import '../../core/player/player_service.dart';
import '../../core/player/lyrics_engine.dart';
import '../../core/storage/database.dart';

/// 数据库 Provider
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

/// 音源管理器
final sourceManagerProvider = Provider<SourceManager>((ref) {
  final manager = SourceManager();
  ref.onDispose(() => manager.dispose());
  return manager;
});

/// 当前活跃音源 id（值类型）。
/// 仅在切换/增删音源时变化，用于驱动 UI 重建，
/// 同时避免 playerService 因音源变化而被级联重建。
final activeEngineIdProvider = StateProvider<String?>((ref) => null);

/// 当前活跃音源引擎（读取用，不作为其它 Provider 的 watch 依赖）。
final activeEngineProvider = Provider<SourceEngine?>((ref) {
  // 依赖 id，使音源切换后此处也能拿到最新引擎
  ref.watch(activeEngineIdProvider);
  return ref.read(sourceManagerProvider).activeEngine;
});

/// 已导入音源列表
final sourceListProvider = FutureProvider<List<SourceEntry>>((ref) async {
  final db = ref.watch(databaseProvider);
  return db.getAllSources();
});

/// 播放器实例 —— 常驻单例。
/// 关键：不 watch 任何音源 Provider，否则切换/导入/删除音源会导致
/// 整个 PlayerService 被 dispose 重建，正在播放的音乐中断、队列丢失。
/// 音源引擎通过 setSourceEngine() 在运行时注入。
final playerServiceProvider = Provider<PlayerService>((ref) {
  final player = PlayerService();
  // 初始注入当前活跃音源
  player.setSourceEngine(ref.read(sourceManagerProvider).activeEngine);
  // 监听活跃音源 id 变化：只重新注入引擎，不重建播放器
  ref.listen<String?>(activeEngineIdProvider, (prev, next) {
    player.setSourceEngine(ref.read(sourceManagerProvider).activeEngine);
  });
  // 播放历史落库：把歌曲 upsert 进 songs 表再记录
  player.onPlayRecorded = (music) {
    final db = ref.read(databaseProvider);
    db.upsertSong(
      musicId: music.id,
      source: music.source,
      name: music.name,
      singer: music.singer,
      album: music.album,
      img: music.img,
      interval: music.interval ?? 0,
      hash: music.hash,
    ).then((songId) => db.recordPlay(songId));
  };
  ref.onDispose(() => player.dispose());
  return player;
});

/// 统一播放入口：设置播放队列并从指定索引开始播放。
/// 这是所有"点播"动作（搜索/收藏/历史/歌单/本地）的唯一入口。
void playQueue(WidgetRef ref, List<MusicInfo> queue, {int startIndex = 0}) {
  if (queue.isEmpty) return;
  ref.read(playerServiceProvider).setQueue(queue, startIndex: startIndex);
  // 同步 UI 队列，供队列面板等展示
  ref.read(playQueueProvider.notifier).setQueue(queue, startIndex: startIndex);
}

/// 收藏歌曲 id 集合（驱动收藏图标状态）。
/// 增删收藏后调用 ref.invalidate(favoritesProvider) 刷新。
final favoritesProvider = FutureProvider<Set<String>>((ref) async {
  final db = ref.watch(databaseProvider);
  final list = await db.getFavorites();
  return list.map((s) => s.id).toSet();
});

/// 切换某首歌的收藏状态，返回切换后是否已收藏。
Future<bool> toggleFavorite(WidgetRef ref, MusicInfo music) async {
  final db = ref.read(databaseProvider);
  final songId = await db.upsertSong(
    musicId: music.id,
    source: music.source,
    name: music.name,
    singer: music.singer,
    album: music.album,
    img: music.img,
    interval: music.interval ?? 0,
    hash: music.hash,
  );
  final fav = await db.isFavorite(songId);
  if (fav) {
    await db.removeFavorite(songId);
  } else {
    await db.addFavorite(songId);
  }
  ref.invalidate(favoritesProvider);
  return !fav;
}

/// 播放器状态
final playerStateProvider = StreamProvider<PlayerStateData>((ref) async* {
  final player = ref.watch(playerServiceProvider);
  yield* player.stateStream;
});

/// 歌词状态
final lyricsStateProvider = StreamProvider<LyricState>((ref) async* {
  final player = ref.watch(playerServiceProvider);
  yield* player.lyricsStream;
});

/// 搜索结果
final searchResultsProvider =
    StateNotifierProvider<SearchNotifier, AsyncValue<List<MusicInfo>>>((ref) {
  return SearchNotifier(ref);
});

class SearchNotifier extends StateNotifier<AsyncValue<List<MusicInfo>>> {
  final Ref _ref;
  SearchNotifier(this._ref) : super(const AsyncValue.data([]));

  Future<void> search(String keyword, {String platform = 'kw'}) async {
    if (keyword.trim().isEmpty) {
      state = const AsyncValue.data([]);
      return;
    }
    state = const AsyncValue.loading();
    try {
      final engine = _ref.read(activeEngineProvider);
      if (engine == null) {
        state = AsyncValue.error('未加载音源，请先在设置中导入', StackTrace.current);
        return;
      }
      final results = await engine.search(source: platform, keyword: keyword);
      state = AsyncValue.data(results);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void clear() {
    state = const AsyncValue.data([]);
  }
}

/// 播放队列
final playQueueProvider = StateNotifierProvider<QueueNotifier, List<MusicInfo>>((ref) {
  return QueueNotifier();
});

class QueueNotifier extends StateNotifier<List<MusicInfo>> {
  QueueNotifier() : super([]);

  void setQueue(List<MusicInfo> q, {int startIndex = 0}) {
    if (q.isEmpty) {
      state = [];
      return;
    }
    state = List.from(q);
  }

  void add(MusicInfo m) => state = [...state, m];

  /// 插入到下一首播放位置（当前歌之后）。
  /// 播放队列以 PlayerService 为准，此方法由 PlayerService.insertNext 驱动 UI 同步。
  void insertNextAt(MusicInfo m, int currentIndex) {
    if (currentIndex >= 0 && currentIndex < state.length - 1) {
      state = [...state.sublist(0, currentIndex + 1), m, ...state.sublist(currentIndex + 1)];
    } else {
      state = [...state, m];
    }
  }

  void removeAt(int i) {
    if (i < 0 || i >= state.length) return;
    state = [...state.sublist(0, i), ...state.sublist(i + 1)];
  }
  void clear() => state = [];
}

/// 下一首播放：同步更新 PlayerService 队列与 UI 队列。
void insertNextToPlay(WidgetRef ref, MusicInfo music) {
  final player = ref.read(playerServiceProvider);
  player.insertNext(music);
  ref.read(playQueueProvider.notifier).insertNextAt(music, player.currentState.currentIndex);
}

/// 应用设置
final appSettingsProvider =
    StateNotifierProvider<AppSettingsNotifier, AppSettings>((ref) {
  return AppSettingsNotifier();
});

class AppSettings {
  final bool darkMode;
  final String defaultQuality;
  final bool desktopLyrics;
  final int cacheLimitMB;
  final bool autoUpdateSources;
  final int themeColor; // 主题色 ARGB 值

  const AppSettings({
    this.darkMode = false,
    this.defaultQuality = '128k',
    this.desktopLyrics = false,
    this.cacheLimitMB = 500,
    this.autoUpdateSources = true,
    this.themeColor = 0xFF6750A4,
  });

  AppSettings copyWith({
    bool? darkMode,
    String? defaultQuality,
    bool? desktopLyrics,
    int? cacheLimitMB,
    bool? autoUpdateSources,
    int? themeColor,
  }) {
    return AppSettings(
      darkMode: darkMode ?? this.darkMode,
      defaultQuality: defaultQuality ?? this.defaultQuality,
      desktopLyrics: desktopLyrics ?? this.desktopLyrics,
      cacheLimitMB: cacheLimitMB ?? this.cacheLimitMB,
      autoUpdateSources: autoUpdateSources ?? this.autoUpdateSources,
      themeColor: themeColor ?? this.themeColor,
    );
  }
}

class AppSettingsNotifier extends StateNotifier<AppSettings> {
  AppSettingsNotifier() : super(const AppSettings()) {
    _load();
  }

  static const _kDarkMode = 'pref_darkMode';
  static const _kQuality = 'pref_defaultQuality';
  static const _kDesktopLyrics = 'pref_desktopLyrics';
  static const _kCacheLimit = 'pref_cacheLimitMB';
  static const _kAutoUpdate = 'pref_autoUpdateSources';
  static const _kThemeColor = 'pref_themeColor';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = AppSettings(
      darkMode: prefs.getBool(_kDarkMode) ?? false,
      defaultQuality: prefs.getString(_kQuality) ?? '128k',
      desktopLyrics: prefs.getBool(_kDesktopLyrics) ?? false,
      cacheLimitMB: prefs.getInt(_kCacheLimit) ?? 500,
      autoUpdateSources: prefs.getBool(_kAutoUpdate) ?? true,
      themeColor: prefs.getInt(_kThemeColor) ?? 0xFF6750A4,
    );
  }

  Future<void> _save(void Function(SharedPreferences p) write) async {
    final prefs = await SharedPreferences.getInstance();
    write(prefs);
  }

  void setDarkMode(bool v) {
    state = state.copyWith(darkMode: v);
    _save((p) => p.setBool(_kDarkMode, v));
  }

  void setDefaultQuality(String v) {
    state = state.copyWith(defaultQuality: v);
    _save((p) => p.setString(_kQuality, v));
  }

  void setDesktopLyrics(bool v) {
    state = state.copyWith(desktopLyrics: v);
    _save((p) => p.setBool(_kDesktopLyrics, v));
  }

  void setCacheLimit(int mb) {
    state = state.copyWith(cacheLimitMB: mb);
    _save((p) => p.setInt(_kCacheLimit, mb));
  }

  void setAutoUpdateSources(bool v) {
    state = state.copyWith(autoUpdateSources: v);
    _save((p) => p.setBool(_kAutoUpdate, v));
  }

  void setThemeColor(int argb) {
    state = state.copyWith(themeColor: argb);
    _save((p) => p.setInt(_kThemeColor, argb));
  }
}
