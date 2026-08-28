import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/providers/providers.dart';
import 'package:go_router/go_router.dart';

/// 全局底部迷你播放条
class MiniPlayerBar extends ConsumerWidget {
  const MiniPlayerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerStateProvider);

    return playerState.when(
      data: (state) {
        if (state.currentMusic == null) return const SizedBox.shrink();

        return Material(
          elevation: 8,
          child: Container(
            height: 64,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                top: BorderSide(color: Theme.of(context).dividerColor, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                // 封面
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: state.currentMusic!.img != null && state.currentMusic!.img!.isNotEmpty
                        ? Image.network(state.currentMusic!.img!, width: 48, height: 48, fit: BoxFit.cover)
                        : Container(
                            width: 48, height: 48,
                            color: Theme.of(context).colorScheme.primaryContainer,
                            child: const Icon(Icons.music_note, size: 24),
                          ),
                  ),
                ),
                // 歌曲信息
                Expanded(
                  child: GestureDetector(
                    onTap: () => context.push('/player'),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          state.currentMusic!.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        Text(
                          state.currentMusic!.singer,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                // 进度
                SizedBox(
                  width: 40,
                  child: CircularProgressIndicator(
                    value: state.duration.inSeconds > 0
                        ? state.position.inSeconds / state.duration.inSeconds
                        : 0,
                    strokeWidth: 2,
                  ),
                ),
                // 播放/暂停按钮
                IconButton(
                  icon: Icon(state.isPlaying ? Icons.pause : Icons.play_arrow),
                  onPressed: () {},
                ),
                // 下一曲
                IconButton(
                  icon: const Icon(Icons.skip_next),
                  onPressed: () {},
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
