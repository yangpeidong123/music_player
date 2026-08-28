import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/providers/providers.dart';
import '../../shared/widgets/mini_player_bar.dart';
import 'package:go_router/go_router.dart';

class PlaylistPage extends ConsumerStatefulWidget {
  final String? playlistId;
  const PlaylistPage({super.key, this.playlistId});

  @override
  ConsumerState<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends ConsumerState<PlaylistPage> {
  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);
    final playlists = db.getAllPlaylists();

    return Scaffold(
      appBar: AppBar(
        title: const Text('歌单'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showCreateDialog(context, db),
          ),
        ],
      ),
      body: FutureBuilder(
        future: playlists,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final list = snapshot.data!;
          if (list.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.playlist_add, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('还没有歌单'),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () => _showCreateDialog(context, db),
                    icon: const Icon(Icons.add),
                    label: const Text('创建歌单'),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (context, index) {
              final pl = list[index];
              return ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: pl.cover != null && pl.cover!.isNotEmpty
                      ? Image.network(pl.cover!, width: 56, height: 56, fit: BoxFit.cover)
                      : Container(
                          width: 56, height: 56,
                          color: Theme.of(context).colorScheme.primaryContainer,
                          child: const Icon(Icons.playlist_play),
                        ),
                ),
                title: Text(pl.name),
                subtitle: Text(pl.description.isNotEmpty ? pl.description : '点击查看'),
                trailing: PopupMenuButton(
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'rename', child: Text('重命名')),
                    const PopupMenuItem(value: 'delete', child: Text('删除')),
                  ],
                  onSelected: (value) {
                    if (value == 'rename') _showRenameDialog(context, db, pl);
                    if (value == 'delete') db.deletePlaylist(pl.id);
                  },
                ),
                onTap: () {
                  // 导航到歌单详情
                },
              );
            },
          );
        },
      ),
      bottomNavigationBar: const MiniPlayerBar(),
    );
  }

  void _showCreateDialog(BuildContext context, dynamic db) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('创建歌单'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: '歌单名称'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                db.createPlaylist(controller.text);
                Navigator.pop(context);
                setState(() {});
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(BuildContext context, dynamic db, dynamic playlist) {
    final controller = TextEditingController(text: playlist.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                db.renamePlaylist(playlist.id, controller.text);
                Navigator.pop(context);
                setState(() {});
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}
