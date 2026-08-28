import 'package:flutter_riverpod/flutter_riverpod.dart';
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

/// 当前活跃音源引擎
final activeEngineProvider = Provider<SourceEngine?>((ref) {
  return ref.watch(sourceManagerProvider).activeEngine;
});

/// 已导入音源列表
final sourceListProvider = FutureProvider<List<SourceEntry>>((ref) async {
  final db = ref.watch(databaseProvider);
  return db.getAllSources();
});

/// 播放器实例
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
final searchResultsProvider = StateNotifierProvider<SearchNotifier, AsyncValue<List<MusicInfo>>>((ref) {
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
        state = AsyncValue.error('未加载音源', StackTrace.current);
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
  void setQueue(List<MusicInfo> q) => state = List.from(q);
  void add(MusicInfo m) => state = [...state, m];
  void removeAt(int i) {
    if (i < 0 || i >= state.length) return;
    state = [...state.sublist(0, i), ...state.sublist(i + 1)];
  }
  void clear() => state = [];
}

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
  const AppSettings({this.darkMode = false, this.defaultQuality = '128k', this.desktopLyrics = false, this.cacheLimitMB = 500, this.autoUpdateSources = true});
  AppSettings copyWith({bool? darkMode, String? defaultQuality, bool? desktopLyrics, int? cacheLimitMB, bool? autoUpdateSources}) {
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
  void setDarkMode(bool v) => state = state.copyWith(darkMode: v);
  void setDefaultQuality(String v) => state = state.copyWith(defaultQuality: v);
  void setDesktopLyrics(bool v) => state = state.copyWith(desktopLyrics: v);
  void setCacheLimit(int mb) => state = state.copyWith(cacheLimitMB: mb);
  void setAutoUpdateSources(bool v) => state = state.copyWith(autoUpdateSources: v);
}
