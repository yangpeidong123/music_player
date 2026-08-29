import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/engine/source_engine.dart';
import '../../shared/providers/providers.dart';
import '../../shared/widgets/mini_player_bar.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.watch(sourceManagerProvider);
    final sources = manager.sources;
    final activeEngine = ref.watch(activeEngineProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('音乐'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => context.push('/search'),
            tooltip: '搜索',
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
            tooltip: '设置',
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          // 欢迎卡片
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            sliver: SliverToBoxAdapter(
              child: _buildWelcomeCard(context, sources, activeEngine, theme),
            ),
          ),
          // 快捷入口
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverGrid.count(
              crossAxisCount: 2,
              childAspectRatio: 2.5,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: [
                _buildQuickCard(context, Icons.search, '搜索音乐', '搜你想听', () => context.push('/search')),
                _buildQuickCard(context, Icons.favorite, '我的收藏', '收藏的歌曲', () => context.push('/favorites')),
                _buildQuickCard(context, Icons.history, '播放历史', '最近播放', () => context.push('/history')),
                _buildQuickCard(context, Icons.playlist_play, '我的歌单', '收藏的歌单', () => context.push('/playlists')),
              ].animate(interval: 50.ms).fadeIn(duration: 300.ms).slideY(begin: 0.1, end: 0),
            ),
          ),
          // 音源状态
          if (sources.isNotEmpty) ...[
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(
                child: Text(
                  '已导入音源 (${sources.length})',
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final s = sources[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: const Icon(Icons.source),
                      ),
                      title: Text(s.name),
                      subtitle: Text('v${s.version} · by ${s.author}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/settings/sources'),
                    ),
                  );
                },
                childCount: sources.length,
              ),
            ),
          ] else
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverToBoxAdapter(
                child: _buildNoSourceState(context),
              ),
            ),
        ],
      ),
      bottomNavigationBar: const MiniPlayerBar(),
    );
  }

  Widget _buildWelcomeCard(
    BuildContext context,
    List<SourceMeta> sources,
    SourceEngine? activeEngine,
    ThemeData theme,
  ) {
    final hour = DateTime.now().hour;
    final greeting = hour < 6
        ? '夜深了'
        : hour < 12
            ? '早上好'
            : hour < 18
                ? '下午好'
                : '晚上好';
    final message = activeEngine == null
        ? '未加载音源，请先导入'
        : '已准备就绪，开始探索音乐吧';

    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    greeting,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.music_note,
              size: 48,
              color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 400.ms).slideX(begin: -0.05, end: 0);
  }

  Widget _buildQuickCard(
    BuildContext context,
    IconData icon,
    String label,
    String subtitle,
    VoidCallback onTap,
  ) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(icon, color: theme.colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: theme.textTheme.titleSmall),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNoSourceState(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: ListTile(
        leading: const Icon(Icons.source_outlined),
        title: const Text('导入洛雪音源'),
        subtitle: const Text('点击设置中的「音源管理」导入'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/settings/sources'),
      ),
    );
  }
}
