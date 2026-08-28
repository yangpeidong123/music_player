import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/engine/source_engine.dart';
import '../../core/engine/source_manager.dart';
import '../../core/player/player_service.dart';
import '../../core/storage/database.dart';
import '../../core/storage/source_storage.dart';

/// 数据库 Provider
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

/// 音源管理器 Provider
final sourceManagerProvider = Provider<SourceManager>((ref) {
  final manager = SourceManager();
  ref.onDispose(() => manager.dispose());
  return manager;
});

/// 音源持久化 Provider
final sourceStorageProvider = Provider<SourceStorage>((ref) {
  final db = ref.watch(databaseProvider);
  final manager = ref.watch(sourceManagerProvider);
  return SourceStorage(db, manager);
});

/// 当前活跃音源引擎
final activeEngineProvider = Provider<SourceEngine?>((ref) {
  return ref.watch(sourceManagerProvider).activeEngine;
});

/// 已加载音源列表（从数据库）
final sourceListProvider = FutureProvider<List<SourceEntry>>((ref) async {
  final db = ref.watch(databaseProvider);
  return db.getAllSources();
});

/// 播放器实例 Provider
final playerServiceProvider = Provider<PlayerService>((ref) {
  final engine = ref.watch(activeEngineProvider);
  final player = PlayerService(sourceEngine: engine);
  ref.onDispose(() => player.dispose());
  return player;
});

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
}

/// 播放队列
final playQueueProvider = StateNotifierProvider<QueueNotifier, List<MusicInfo>>((ref) {
  return QueueNotifier();
});

class QueueNotifier extends StateNotifier<List<MusicInfo>> {
  QueueNotifier() : super([]);

  void setQueue(List<MusicInfo> queue) => state = List.from(queue);
  void add(MusicInfo music) => state = [...state, music];
  void removeAt(int index) {
    if (index < 0 || index >= state.length) return;
    state = [...state.sublist(0, index), ...state.sublist(index + 1)];
  }
  void clear() => state = [];
}

/// 默认音质
final defaultQualityProvider = StateProvider<String>((ref) => '128k');

/// 定时关闭剩余时间
final sleepTimerProvider = StateProvider<Duration?>((ref) => null);

/// 应用设置
final appSettingsProvider = StateNotifierProvider<AppSettingsNotifier, AppSettings>((ref) {
  return AppSettingsNotifier();
});

class AppSettings {
  final bool darkMode;
  final String defaultQuality;
  final bool desktopLyrics;
  final int cacheLimitMB;
  final bool autoUpdateSources;

  const AppSettings({
    this.darkMode = false,
    this.defaultQuality = '128k',
    this.desktopLyrics = false,
    this.cacheLimitMB = 500,
    this.autoUpdateSources = true,
  });

  AppSettings copyWith({
    bool? darkMode,
    String? defaultQuality,
    bool? desktopLyrics,
    int? cacheLimitMB,
    bool? autoUpdateSources,
  }) {
    return AppSettings(
      darkMode: darkMode ?? this.darkMode,
      defaultQuality: defaultQuality ?? this.defaultQuality,
      desktopLyrics: desktopLyrics ?? this.desktopLyrics,
      cacheLimitMB: cacheLimitMB ?? this.cacheLimitMB,
      autoUpdateSources: autoUpdateSources ?? this.autoUpdateSources,
    );
  }
}

class AppSettingsNotifier extends StateNotifier<AppSettings> {
  AppSettingsNotifier() : super(const AppSettings());

  void setDarkMode(bool value) => state = state.copyWith(darkMode: value);
  void setDefaultQuality(String value) => state = state.copyWith(defaultQuality: value);
  void setDesktopLyrics(bool value) => state = state.copyWith(desktopLyrics: value);
  void setCacheLimit(int mb) => state = state.copyWith(cacheLimitMB: mb);
  void setAutoUpdateSources(bool value) => state = state.copyWith(autoUpdateSources: value);
}
