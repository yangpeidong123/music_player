import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/engine/source_engine.dart';
import '../../shared/providers/providers.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  String _platform = 'kw';
  String _lastKeyword = '';

  // 搜索历史
  List<String> _history = [];
  // 热搜
  final List<String> _hotSearches = [
    '周杰伦', '陈奕迅', '薛之谦', '林俊杰', '邓紫棋',
    'Taylor Swift', 'Ed Sheeran', 'Adele', 'Coldplay', 'Imagine Dragons',
  ];

  // 防抖
  DateTime? _lastSearchTime;
  String _pendingQuery = '';

  static const _platforms = [
    {'id': 'kw', 'name': '酷我'},
    {'id': 'wy', 'name': '网易云'},
    {'id': 'kg', 'name': '酷狗'},
    {'id': 'tx', 'name': '企鹅'},
    {'id': 'mg', 'name': '咪咕'},
  ];

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _doSearch([String? keyword]) {
    final k = (keyword ?? _controller.text).trim();
    if (k.isEmpty) return;
    if (k == _lastKeyword) return;

    setState(() {
      _lastKeyword = k;
      if (!_history.contains(k)) {
        _history.insert(0, k);
        if (_history.length > 10) _history = _history.sublist(0, 10);
      }
    });

    // 触发搜索
    ref.read(searchResultsProvider.notifier).search(k, platform: _platform);
  }

  void _clearHistory() {
    setState(() => _history = []);
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(searchResultsProvider);
    final hasQuery = _lastKeyword.isNotEmpty;
    final activeEngine = ref.watch(activeEngineProvider);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          focusNode: _focusNode,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '搜索歌曲、歌手',
            border: InputBorder.none,
          ),
          textInputAction: TextInputAction.search,
          onSubmitted: _doSearch,
          onChanged: _onQueryChanged,
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                _controller.clear();
                setState(() => _lastKeyword = '');
                _focusNode.requestFocus();
              },
            ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _doSearch(),
            tooltip: '搜索',
          ),
        ],
      ),
      body: Column(
        children: [
          // 平台选择
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: _platforms.map((p) {
                final selected = _platform == p['id'];
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(p['name']!),
                    selected: selected,
                    onSelected: (_) {
                      setState(() => _platform = p['id']!);
                      if (_lastKeyword.isNotEmpty) _doSearch();
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          // 主内容
          Expanded(
            child: hasQuery
                ? _buildSearchResults(context, results, activeEngine)
                : _buildSuggestions(context),
          ),
        ],
      ),
    );
  }

  void _onQueryChanged(String value) {
    setState(() {}); // 更新清空按钮
    if (value.trim().isEmpty) return;
    _pendingQuery = value;
    _lastSearchTime = DateTime.now();
    // 简单的 debounce
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_lastSearchTime != null &&
          DateTime.now().difference(_lastSearchTime!) >= const Duration(milliseconds: 280)) {
        _doSearch();
      }
    });
  }

  Widget _buildSearchResults(BuildContext context, AsyncValue<List<MusicInfo>> results, SourceEngine? engine) {
    if (engine == null) {
      return _buildNoEngineState(context);
    }
    return results.when(
      data: (list) {
        if (list.isEmpty) {
          return _buildEmptyResults(context);
        }
        return ListView.separated(
          itemCount: list.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final music = list[index];
            return _buildSongTile(context, music, index);
          },
        );
      },
      loading: () => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('搜索 "$_lastKeyword"...', style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
      error: (err, _) => _buildErrorState(context, err),
    );
  }

  Widget _buildEmptyResults(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 64, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text('未找到 "$_lastKeyword" 的相关结果', style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, Object err) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text('搜索失败: $err', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _doSearch,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoEngineState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.library_music_outlined, size: 48, color: Colors.orange),
            const SizedBox(height: 16),
            const Text('未加载音源', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            const Text('请先在设置中导入洛雪音源', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/settings/sources'),
              icon: const Icon(Icons.settings),
              label: const Text('去导入'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestions(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_history.isNotEmpty) ...[
          Row(
            children: [
              Text('搜索历史', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              TextButton(
                onPressed: _clearHistory,
                child: const Text('清空'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _history.map((h) {
              return ActionChip(
                label: Text(h),
                onPressed: () {
                  _controller.text = h;
                  _doSearch();
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
        ],
        Text('热门搜索', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _hotSearches.map((h) {
            return ActionChip(
              avatar: const Icon(Icons.local_fire_department, size: 16, color: Colors.orange),
              label: Text(h),
              onPressed: () {
                _controller.text = h;
                _doSearch();
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSongTile(BuildContext context, MusicInfo music, int index) {
    return ListTile(
      leading: ClipRRect(
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
      title: Text(
        music.name,
        maxLines: 1, overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${music.singer}${music.album.isNotEmpty ? ' · ${music.album}' : ''}',
        maxLines: 1, overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        music.interval != null ? _formatDuration(Duration(seconds: music.interval!)) : '',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      onTap: () {
        // 播放这首歌和当前列表
        final currentList = ref.read(searchResultsProvider).value ?? [];
        ref.read(playQueueProvider.notifier).setQueue(currentList, startIndex: index);
        Navigator.pushNamed(context, '/player');
      },
    );
  }

  Widget _albumPlaceholder(BuildContext context) {
    return Container(
      width: 48, height: 48,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.music_note, size: 24),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
