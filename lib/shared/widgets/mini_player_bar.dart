import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../providers/providers.dart';

/// 全局底部迷你播放条
class MiniPlayerBar extends ConsumerWidget {
  const MiniPlayerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerStateProvider);

    return playerState.when(
      data: (state) {
        final music = state.currentMusic;
        if (music == null) return const SizedBox.shrink();

        return Material(
          elevation: 8,
          child: Container(
            height: 64,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).dividerColor,
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              children: [
                // 封面
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: GestureDetector(
                    onTap: () => context.push('/player'),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: music.img != null && music.img!.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: music.img!,
                              width: 48, height: 48, fit: BoxFit.cover,
                              placeholder: (_, __) => _albumPlaceholder(context),
                              errorWidget: (_, __, ___) => _albumPlaceholder(context),
                            )
                          : _albumPlaceholder(context),
                    ),
                  ),
                ),
                // 歌曲信息 + 进度
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        music.name,
                        style: Theme.of(context).textTheme.bodyMedium,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        music.singer,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // 进度
                if (state.duration.inMilliseconds > 0)
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      value: state.duration.inMilliseconds > 0
                          ? state.position.inMilliseconds / state.duration.inMilliseconds
                          : 0,
                      strokeWidth: 2,
                      backgroundColor: Theme.of(context).dividerColor,
                    ),
                  ),
                const SizedBox(width: 4),
                // 控制
                IconButton(
                  icon: Icon(state.isPlaying ? Icons.pause : Icons.play_arrow),
                  onPressed: () => ref.read(playerServiceProvider).playOrPause(),
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next),
                  onPressed: () => ref.read(playerServiceProvider).next(),
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

  Widget _albumPlaceholder(BuildContext context) {
    return Container(
      width: 48, height: 48,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.music_note, size: 24),
    );
  }
}
