import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../shared/providers/providers.dart';
import '../../shared/widgets/mini_player_bar.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('音乐'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => context.push('/search'),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          // 快捷入口
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverGrid.count(
              crossAxisCount: 2,
              childAspectRatio: 2.5,
              children: [
                _buildQuickCard(context, Icons.search, '搜索音乐', () => context.push('/search')),
                _buildQuickCard(context, Icons.library_music, '本地音乐', () {}),
                _buildQuickCard(context, Icons.playlist_play, '播放历史', () {}),
                _buildQuickCard(context, Icons.favorite, '我的收藏', () {}),
              ],
            ),
          ),
          // 音源状态
          SliverToBoxAdapter(
            child: _buildSourceStatus(context, ref),
          ),
        ],
      ),
      bottomNavigationBar: const MiniPlayerBar(),
    );
  }

  Widget _buildQuickCard(BuildContext context, IconData icon, String label, VoidCallback onTap) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.all(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Text(label, style: theme.textTheme.titleSmall),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSourceStatus(BuildContext context, WidgetRef ref) {
    final manager = ref.watch(sourceManagerProvider);
    final sources = manager.sources;

    if (sources.isEmpty) {
      return Card(
        margin: const EdgeInsets.all(16),
        child: ListTile(
          leading: const Icon(Icons.source),
          title: const Text('未导入音源'),
          subtitle: const Text('点击设置中的「音源管理」导入洛雪音源'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/settings/sources'),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('已导入音源 (${sources.length})', style: Theme.of(context).textTheme.titleMedium),
          ),
          ...sources.map((s) => ListTile(
                leading: const CircleAvatar(child: Icon(Icons.source)),
                title: Text(s.name),
                subtitle: Text('v${s.version} by ${s.author}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/settings/sources'),
              )),
        ],
      ),
    );
  }
}
