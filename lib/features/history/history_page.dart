import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../shared/providers/providers.dart';
import '../../shared/widgets/mini_player_bar.dart';

class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});
  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('播放历史'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('清空历史'),
                  content: const Text('确定要清空所有播放历史吗？'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
                    FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('确定')),
                  ],
                ),
              );
              if (ok == true) { await db.clearHistory(); setState(() {}); }
            },
          ),
        ],
      ),
      body: FutureBuilder(
        future: db.getPlayHistory(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final list = snapshot.data!;
          if (list.isEmpty) return const Center(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.history, size: 64, color: Colors.grey),
              SizedBox(height: 16), Text('还没有播放记录'),
            ]),
          );
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (context, index) {
              final song = list[index];
              return ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: song.img != null
                      ? Image.network(song.img!, width: 48, height: 48, fit: BoxFit.cover)
                      : Container(width: 48, height: 48,
                          color: Theme.of(context).colorScheme.primaryContainer,
                          child: const Icon(Icons.music_note)),
                ),
                title: Text(song.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(song.singer, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Text('${song.interval}s'),
                onTap: () {
                  // 点播：把整个历史列表作为播放队列，从当前这首开始
                  final queue = list.map((s) => s.toMusicInfo()).toList();
                  playQueue(ref, queue, startIndex: index);
                  context.push('/player');
                },
              );
            },
          );
        },
      ),
      bottomNavigationBar: const MiniPlayerBar(),
    );
  }
}
