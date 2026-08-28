import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../shared/providers/providers.dart';
import '../../shared/widgets/mini_player_bar.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();
  String _platform = 'kw'; // 默认酷我

  final _platforms = [
    {'id': 'kw', 'name': '酷我'},
    {'id': 'wy', 'name': '网易云'},
    {'id': 'kg', 'name': '酷狗'},
    {'id': 'tx', 'name': '企鹅'},
    {'id': 'mg', 'name': '咪咕'},
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _doSearch() {
    final keyword = _controller.text.trim();
    if (keyword.isEmpty) return;
    ref.read(searchResultsProvider.notifier).search(keyword, platform: _platform);
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(searchResultsProvider);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          decoration: const InputDecoration(
            hintText: '搜索歌曲、歌手',
            border: InputBorder.none,
          ),
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _doSearch(),
        ),
        actions: [
          IconButton(onPressed: _doSearch, icon: const Icon(Icons.search)),
        ],
      ),
      body: Column(
        children: [
          // 平台选择
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: _platforms.map((p) {
                final selected = _platform == p['id'];
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(p['name']!),
                    selected: selected,
                    onSelected: (_) => setState(() => _platform = p['id']!),
                  ),
                );
              }).toList(),
            ),
          ),
          // 搜索结果
          Expanded(
            child: results.when(
              data: (list) => list.isEmpty
                  ? const Center(child: Text('暂无结果'))
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (context, index) {
                        final music = list[index];
                        return ListTile(
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: music.img != null && music.img!.isNotEmpty
                                ? Image.network(music.img!, width: 48, height: 48, fit: BoxFit.cover)
                                : Container(
                                    width: 48, height: 48,
                                    color: Theme.of(context).colorScheme.primaryContainer,
                                    child: const Icon(Icons.music_note),
                                  ),
                          ),
                          title: Text(music.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(music.singer, maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: Text('${music.interval ?? 0}s'),
                          onTap: () {
                            ref.read(playQueueProvider.notifier).setQueue(list);
                            context.push('/player');
                          },
                        );
                      },
                    ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 48),
                    const SizedBox(height: 8),
                    Text(err.toString()),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: _doSearch, child: const Text('重试')),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const MiniPlayerBar(),
    );
  }
}
