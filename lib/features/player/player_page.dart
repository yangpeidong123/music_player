import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/player/player_service.dart';
import '../../core/player/lyrics_engine.dart';
import '../../shared/providers/providers.dart';

/// 全屏播放器
class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({super.key});

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage>
    with SingleTickerProviderStateMixin {
  bool _showLyrics = false;
  late final AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(playerStateProvider);
    final lyricState = ref.watch(lyricsStateProvider);
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: playerState.when(
          data: (state) => _buildContent(context, state, lyricState, theme),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text('播放器错误: $e'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    PlayerStateData state,
    LyricState lyricState,
    ThemeData theme,
  ) {
    final music = state.currentMusic;
    if (music == null) {
      return const Center(child: Text('未选择歌曲'));
    }

    return Column(
      children: [
        _buildTopBar(context, state),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: _showLyrics
                ? _buildLyricsView(lyricState, theme, key: const ValueKey('lyrics'))
                : _buildAlbumView(state, music, theme, key: const ValueKey('album')),
          ),
        ),
        _buildSongInfo(music, state, theme),
        _buildProgressBar(state, theme),
        _buildControls(state, theme),
        _buildBottomBar(context, state, theme),
      ],
    );
  }

  Widget _buildTopBar(BuildContext context, PlayerStateData state) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.keyboard_arrow_down, size: 32),
          onPressed: () => Navigator.pop(context),
          tooltip: '收起',
        ),
        const Spacer(),
        Text('正在播放', style: Theme.of(context).textTheme.titleSmall),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.more_vert),
          onPressed: () => _showOptions(context),
          tooltip: '更多',
        ),
      ],
    );
  }

  Widget _buildAlbumView(
    PlayerStateData state,
    dynamic music,
    ThemeData theme, {
    required Key key,
  }) {
    final imgUrl = music.img;
    return Center(
      key: key,
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: AspectRatio(
          aspectRatio: 1,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 旋转封面
              if (state.isPlaying)
                RotationTransition(
                  turns: _rotationController,
                  child: _buildAlbumArt(imgUrl, 80, theme),
                )
              else
                _buildAlbumArt(imgUrl, 80, theme),
              // 中心圆盘
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.surface,
                  border: Border.all(color: theme.dividerColor, width: 2),
                ),
                child: const Icon(Icons.music_note, size: 32),
              ),
            ],
          ),
        ),
      ),
    ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack);
  }

  Widget _buildAlbumArt(String? url, double size, ThemeData theme) {
    if (url == null || url.isEmpty) {
      return Container(
        width: size * 3.5, height: size * 3.5,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: theme.colorScheme.primaryContainer,
        ),
        child: Icon(Icons.music_note, size: size),
      );
    }
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url,
        width: size * 3.5,
        height: size * 3.5,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(
          width: size * 3.5, height: size * 3.5,
          color: theme.colorScheme.surfaceContainerHighest,
        ),
        errorWidget: (_, __, ___) => Container(
          width: size * 3.5, height: size * 3.5,
          color: theme.colorScheme.surfaceContainerHighest,
          child: Icon(Icons.music_note, size: size, color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }

  Widget _buildLyricsView(LyricState state, ThemeData theme, {required Key key}) {
    if (!state.hasLyrics) {
      return Center(
        key: key,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lyrics_outlined, size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text('暂无歌词', style: theme.textTheme.bodyMedium),
          ],
        ),
      );
    }

    return GestureDetector(
      key: key,
      onTap: () => setState(() => _showLyrics = false),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 32),
        itemCount: state.lines.length,
        itemBuilder: (context, index) {
          final line = state.lines[index];
          final isCurrent = index == state.currentIndex;
          return AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 300),
            style: TextStyle(
              fontSize: isCurrent ? 18 : 15,
              color: isCurrent
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withValues(alpha: 0.5),
              fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
              height: 1.8,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(line.text),
                  if (line.translation != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      line.translation!,
                      style: TextStyle(
                        fontSize: isCurrent ? 12 : 11,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSongInfo(dynamic music, PlayerStateData state, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  music.name,
                  style: theme.textTheme.titleLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  music.singer,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.favorite_border),
            onPressed: () {
              // TODO: 收藏
            },
            tooltip: '收藏',
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(PlayerStateData state, ThemeData theme) {
    if (state.hasError) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          state.errorMessage!,
          style: TextStyle(color: theme.colorScheme.error),
          textAlign: TextAlign.center,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            ),
            child: Slider(
              value: state.duration.inMilliseconds > 0
                  ? state.position.inMilliseconds.toDouble().clamp(0, state.duration.inMilliseconds.toDouble())
                  : 0,
              max: state.duration.inMilliseconds > 0 ? state.duration.inMilliseconds.toDouble() : 1,
              onChanged: state.processingState == ProcessingState.completed
                  ? null
                  : (v) => seek(Duration(milliseconds: v.toInt())),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatDuration(state.position),
                  style: theme.textTheme.bodySmall),
              Text(_formatDuration(state.duration),
                  style: theme.textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildControls(PlayerStateData state, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            iconSize: 28,
            icon: Icon(_playModeIcon(state.playMode)),
            color: theme.colorScheme.primary,
            onPressed: () => ref.read(playerServiceProvider).cyclePlayMode(),
            tooltip: state.playMode.label,
          ),
          IconButton(
            iconSize: 36,
            icon: const Icon(Icons.skip_previous),
            onPressed: () => ref.read(playerServiceProvider).previous(),
          ),
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.primary,
            ),
            child: IconButton(
              icon: Icon(
                state.isPlaying ? Icons.pause : Icons.play_arrow,
                color: theme.colorScheme.onPrimary,
                size: 40,
              ),
              onPressed: () => ref.read(playerServiceProvider).playOrPause(),
            ),
          ),
          IconButton(
            iconSize: 36,
            icon: const Icon(Icons.skip_next),
            onPressed: () => ref.read(playerServiceProvider).next(),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.queue_music, size: 28),
            onSelected: (v) {
              if (v == 'quality') _showQualityPicker(context, state);
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'quality',
                child: Row(children: [
                  const Icon(Icons.high_quality, size: 18),
                  const SizedBox(width: 8),
                  Text('音质: ${state.quality}'),
                ]),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context, PlayerStateData state, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Row(
        children: [
          IconButton(
            icon: Icon(_showLyrics ? Icons.album : Icons.lyrics_outlined),
            onPressed: () => setState(() => _showLyrics = !_showLyrics),
            tooltip: _showLyrics ? '封面' : '歌词',
          ),
          const Spacer(),
          IconButton(
            icon: Icon(state.queue.isEmpty ? Icons.favorite_border : Icons.favorite, size: 20),
            onPressed: () {},
            tooltip: '收藏',
          ),
          IconButton(
            icon: const Icon(Icons.share, size: 20),
            onPressed: () {},
            tooltip: '分享',
          ),
          IconButton(
            icon: const Icon(Icons.timer_outlined, size: 20),
            onPressed: () => _showSleepTimerDialog(context),
            tooltip: '定时关闭',
          ),
        ],
      ),
    );
  }

  void _showOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.album), title: const Text('查看专辑')),
            ListTile(leading: const Icon(Icons.artist), title: const Text('歌手主页')),
            ListTile(leading: const Icon(Icons.report), title: const Text('歌曲反馈')),
            ListTile(leading: const Icon(Icons.block), title: const Text('不再播放')),
          ],
        ),
      ),
    );
  }

  void _showQualityPicker(BuildContext context, PlayerStateData state) {
    showDialog(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('选择音质'),
        children: ['128k', '320k', 'flac', 'flac24bit']
            .map((q) => RadioListTile<String>(
                  value: q,
                  groupValue: state.quality,
                  title: Text(_qualityLabel(q)),
                  onChanged: (v) {
                    if (v != null) {
                      ref.read(playerServiceProvider).setQuality(v);
                      Navigator.pop(context);
                    }
                  },
                ))
            .toList(),
      ),
    );
  }

  String _qualityLabel(String q) => switch (q) {
        '128k' => '标准 128k',
        '320k' => '高品质 320k',
        'flac' => '无损 FLAC',
        'flac24bit' => 'Hi-Res 24bit',
        _ => q,
      };

  void _showSleepTimerDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('定时关闭'),
        children: [
          _sleepTimerOption('15 分钟', const Duration(minutes: 15)),
          _sleepTimerOption('30 分钟', const Duration(minutes: 30)),
          _sleepTimerOption('60 分钟', const Duration(minutes: 60)),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.cancel),
            title: const Text('取消定时'),
            onTap: () {
              ref.read(playerServiceProvider).cancelSleepTimer();
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  Widget _sleepTimerOption(String label, Duration d) {
    return ListTile(
      leading: const Icon(Icons.timer),
      title: Text(label),
      onTap: () {
        ref.read(playerServiceProvider).startSleepTimer(d);
        Navigator.pop(context);
      },
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  IconData _playModeIcon(PlayMode m) => switch (m) {
        PlayMode.sequence => Icons.repeat,
        PlayMode.loop => Icons.repeat,
        PlayMode.singleLoop => Icons.repeat_one,
        PlayMode.random => Icons.shuffle,
      };
}
