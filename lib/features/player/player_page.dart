import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PlayerPage extends ConsumerWidget {
  const PlayerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerStateProvider);

    return Scaffold(
      body: playerState.when(
        data: (state) {
          final music = state.currentMusic;
          return SafeArea(
            child: Column(
              children: [
                // 顶部导航
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    Text('正在播放', style: Theme.of(context).textTheme.titleSmall),
                    const Spacer(),
                    IconButton(icon: const Icon(Icons.more_vert), onPressed: () {}),
                  ],
                ),
                const Spacer(),
                // 封面
                Container(
                  width: 280, height: 280,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    color: Theme.of(context).colorScheme.primaryContainer,
                  ),
                  child: music?.img != null && music!.img!.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: Image.network(music.img!, fit: BoxFit.cover),
                        )
                      : const Icon(Icons.music_note, size: 120),
                ),
                const SizedBox(height: 32),
                // 歌曲信息
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(music?.name ?? '未播放', style: Theme.of(context).textTheme.headlineSmall),
                            const SizedBox(height: 4),
                            Text(music?.singer ?? '', style: Theme.of(context).textTheme.bodyMedium),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.favorite_border),
                        onPressed: () {},
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // 进度条
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      LinearProgressIndicator(
                        value: state.duration.inSeconds > 0
                            ? state.position.inSeconds / state.duration.inSeconds
                            : 0,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_formatDuration(state.position)),
                          Text(_formatDuration(state.duration)),
                        ],
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // 播放控制
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: Icon(_playModeIcon(state.playMode)),
                      iconSize: 32,
                      onPressed: () {},
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_previous, size: 48),
                      onPressed: () {},
                    ),
                    Container(
                      width: 72, height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      child: IconButton(
                        icon: Icon(
                          state.isPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                        ),
                        iconSize: 36,
                        onPressed: () {},
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next, size: 48),
                      onPressed: () {},
                    ),
                    IconButton(
                      icon: const Icon(Icons.queue_music, size: 28),
                      onPressed: () {},
                    ),
                  ],
                ),
                const Spacer(),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('播放错误: $err')),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  IconData _playModeIcon(PlayMode mode) => switch (mode) {
        PlayMode.sequence => Icons.repeat,
        PlayMode.loop => Icons.repeat,
        PlayMode.singleLoop => Icons.repeat_one,
        PlayMode.random => Icons.shuffle,
      };
}
