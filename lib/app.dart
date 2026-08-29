import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'shared/theme/app_theme.dart';
import 'shared/providers/providers.dart';
import 'features/home/home_page.dart';
import 'features/search/search_page.dart';
import 'features/player/player_page.dart';
import 'features/settings/settings_page.dart';
import 'features/settings/source_manager_page.dart';
import 'features/playlist/playlist_page.dart';
import 'features/history/history_page.dart';
import 'features/favorites/favorites_page.dart';
import 'features/local/local_music_page.dart';

/// 路由配置
final goRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const HomePage()),
    GoRoute(path: '/search', builder: (context, state) => const SearchPage()),
    GoRoute(path: '/player', builder: (context, state) => const PlayerPage()),
    GoRoute(path: '/settings', builder: (context, state) => const SettingsPage()),
    GoRoute(path: '/settings/sources', builder: (context, state) => const SourceManagerPage()),
    GoRoute(path: '/playlists', builder: (context, state) => const PlaylistPage()),
    GoRoute(path: '/history', builder: (context, state) => const HistoryPage()),
    GoRoute(path: '/favorites', builder: (context, state) => const FavoritesPage()),
    GoRoute(path: '/local', builder: (context, state) => const LocalMusicPage()),
  ],
  errorBuilder: (context, state) => Scaffold(
    appBar: AppBar(title: const Text('页面不存在')),
    body: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64),
          const SizedBox(height: 16),
          Text('找不到页面: ${state.uri}'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => GoRouter.of(context).go('/'),
            child: const Text('返回首页'),
          ),
        ],
      ),
    ),
  ),
);

class MusicPlayerApp extends ConsumerWidget {
  const MusicPlayerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final seed = Color(settings.themeColor);

    return MaterialApp.router(
      title: '音乐播放器',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(seed),
      darkTheme: AppTheme.dark(seed),
      themeMode: settings.darkMode ? ThemeMode.dark : ThemeMode.system,
      routerConfig: goRouter,
    );
  }
}
