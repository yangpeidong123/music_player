import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/providers/providers.dart';
import '../../shared/widgets/mini_player_bar.dart';

class FavoritesPage extends ConsumerStatefulWidget {
  const FavoritesPage({super.key});
  @override
  ConsumerState<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends ConsumerState<FavoritesPage> {
  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('我的收藏')),
      body: FutureBuilder(
        future: db.getFavorites(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final list = snapshot.data!;
          if (list.isEmpty) return const Center(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.favorite_border, size: 64, color: Colors.grey),
              SizedBox(height: 16), Text('还没有收藏的歌曲'),
            ]),
          );
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (context, index) {
              final song = list[index];
              return Dismissible(
                key: Key(song.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: Colors.red,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 16),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                onDismissed: (_) {
                  db.removeFavorite(song.id);
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已取消收藏: ${song.name}')),
                  );
                },
                child: ListTile(
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
                  trailing: const Icon(Icons.favorite, color: Colors.red, size: 20),
                  onTap: () {},
                ),
              );
            },
          );
        },
      ),
      bottomNavigationBar: const MiniPlayerBar(),
    );
  }
}
