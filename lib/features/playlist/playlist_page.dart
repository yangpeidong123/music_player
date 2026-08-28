import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/providers/providers.dart';
import '../../shared/widgets/mini_player_bar.dart';

class PlaylistPage extends ConsumerStatefulWidget {
  const PlaylistPage({super.key});
  @override
  ConsumerState<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends ConsumerState<PlaylistPage> {
  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('歌单'),
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: () => _showCreateDialog(db)),
        ],
      ),
      body: FutureBuilder(
        future: db.getAllPlaylists(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final list = snapshot.data!;
          if (list.isEmpty) {
            return Center(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.playlist_add, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                const Text('还没有歌单'),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () => _showCreateDialog(db),
                  icon: const Icon(Icons.add),
                  label: const Text('创建歌单'),
                ),
              ]),
            );
          }
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (context, index) {
              final pl = list[index];
              return ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: pl.cover != null
                      ? Image.network(pl.cover!, width: 56, height: 56, fit: BoxFit.cover)
                      : Container(width: 56, height: 56,
                          color: Theme.of(context).colorScheme.primaryContainer,
                          child: const Icon(Icons.playlist_play)),
                ),
                title: Text(pl.name),
                subtitle: Text(pl.description.isNotEmpty ? pl.description : '点击查看'),
                trailing: PopupMenuButton(
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('重命名')),
                    PopupMenuItem(value: 'delete', child: Text('删除')),
                  ],
                  onSelected: (v) async {
                    if (v == 'rename') _showRenameDialog(pl);
                    if (v == 'delete') { await db.deletePlaylist(pl.id); setState(() {}); }
                  },
                ),
                onTap: () {},
              );
            },
          );
        },
      ),
      bottomNavigationBar: const MiniPlayerBar(),
    );
  }

  void _showCreateDialog(dynamic db) {
    final c = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('创建歌单'),
      content: TextField(controller: c, decoration: const InputDecoration(hintText: '歌单名称'), autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            if (c.text.isNotEmpty) { db.createPlaylist(c.text); Navigator.pop(ctx); setState(() {}); }
          },
          child: const Text('创建'),
        ),
      ],
    ));
  }

  void _showRenameDialog(dynamic pl) {
    final c = TextEditingController(text: pl.name);
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('重命名'),
      content: TextField(controller: c, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(
          onPressed: () async {
            if (c.text.isNotEmpty) {
              await ref.read(databaseProvider).renamePlaylist(pl.id, c.text);
              Navigator.pop(ctx); setState(() {});
            }
          },
          child: const Text('保存'),
        ),
      ],
    ));
  }
}
