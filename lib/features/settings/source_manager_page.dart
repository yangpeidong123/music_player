import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../core/engine/source_engine.dart';
import '../../core/engine/source_manager.dart';
import '../../shared/providers/providers.dart';

class SourceManagerPage extends ConsumerStatefulWidget {
  const SourceManagerPage({super.key});

  @override
  ConsumerState<SourceManagerPage> createState() => _SourceManagerPageState();
}

class _SourceManagerPageState extends ConsumerState<SourceManagerPage> {
  final _urlController = TextEditingController();
  bool _loading = false;

  // 推荐音源
  static const _recommendedSources = [
    {
      'name': '六音',
      'description': '稳定的综合性音源',
      'url': 'https://raw.githubusercontent.com/pdone/lx-music-source/main/sixyin/latest.js',
    },
    {
      'name': '野花',
      'description': '开源综合音源',
      'url': 'https://raw.githubusercontent.com/pdone/lx-music-source/main/flower/latest.js',
    },
  ];

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _importFromUrl(String url) async {
    if (url.isEmpty) {
      _showSnack('请输入音源 URL', isError: true);
      return;
    }

    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      _showSnack('URL 必须以 http:// 或 https:// 开头', isError: true);
      return;
    }

    setState(() => _loading = true);

    try {
      // 下载音源脚本
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
      ));
      final response = await dio.get<String>(url);
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      final script = response.data ?? '';
      if (script.isEmpty) {
        throw Exception('下载的脚本为空');
      }

      // 解析元数据
      final meta = SourceMeta.fromScript(script);
      if (!meta.isValid) {
        throw Exception('脚本缺少 @name 或 @version 元数据');
      }

      // 验证可加载
      final engine = SourceEngine();
      final success = await engine.loadFromScript(script);
      engine.dispose();
      if (!success) {
        throw Exception('音源脚本执行失败，可能不兼容');
      }

      // 保存到数据库
      final db = ref.read(databaseProvider);
      final sourceId = url;
      await db.saveSource(
        id: sourceId,
        name: meta.name,
        url: url,
        script: script,
        version: meta.version,
        author: meta.author,
        homepage: meta.homepage,
        capabilities: '{}',
      );

      // 添加到运行时
      await ref.read(sourceManagerProvider).addSource(script, id: sourceId);
      ref.invalidate(sourceListProvider);

      if (mounted) {
        _urlController.clear();
        _showSnack('音源「${meta.name}」导入成功', isError: false);
      }
    } on SourceLoadException catch (e) {
      _showSnack('导入失败: ${e.message}', isError: true);
    } catch (e) {
      _showSnack('导入失败: $e', isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSnack(String message, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: Duration(seconds: isError ? 4 : 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sourcesAsync = ref.watch(sourceListProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('音源管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _checkUpdates,
            tooltip: '检查更新',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 导入卡片
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('导入音源', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    '粘贴洛雪音源 URL 或选择推荐音源',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _urlController,
                    decoration: InputDecoration(
                      labelText: '音源 URL',
                      hintText: 'https://example.com/source.js',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.link),
                      suffixIcon: _urlController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () => _urlController.clear(),
                            )
                          : null,
                    ),
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(2048),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: _loading ? null : () => _importFromUrl(_urlController.text.trim()),
                        icon: _loading
                            ? const SizedBox(
                                width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.download),
                        label: Text(_loading ? '导入中...' : '导入'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 推荐音源
          Text('推荐音源', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          ..._recommendedSources.map((s) => _buildRecommendedTile(context, s['name']!, s['description']!, s['url']!)),
          const SizedBox(height: 24),
          // 已导入列表
          sourcesAsync.when(
            data: (sources) => sources.isEmpty
                ? const SizedBox.shrink()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('已导入 (${sources.length})', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      ...sources.map((s) => _buildSourceTile(context, s)),
                    ],
                  ),
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (e, _) => Text('加载失败: $e'),
          ),
          const SizedBox(height: 24),
          // 帮助
          Card(
            color: theme.colorScheme.secondaryContainer,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.help_outline),
                      SizedBox(width: 8),
                      Text('什么是音源？', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    '音源是洛雪音乐格式的 JS 脚本，提供各大音乐平台的搜索和播放能力。\n\n'
                    '本应用不内置任何音源，音源由用户自行导入。\n'
                    '导入前请确保音源 URL 来自可信来源。',
                    style: TextStyle(height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendedTile(BuildContext context, String name, String description, String url) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: const Icon(Icons.star),
        ),
        title: Text(name),
        subtitle: Text(description),
        trailing: FilledButton.tonal(
          onPressed: _loading ? null : () => _importFromUrl(url),
          child: const Text('导入'),
        ),
      ),
    );
  }

  Widget _buildSourceTile(BuildContext context, dynamic s) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: s.enabled
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Icon(Icons.source, color: s.enabled ? null : Theme.of(context).colorScheme.outline),
        ),
        title: Text(s.name),
        subtitle: Text('v${s.version} · by ${s.author}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: s.enabled,
              onChanged: (v) async {
                await ref.read(databaseProvider).setSourceEnabled(s.id, v);
                ref.invalidate(sourceListProvider);
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: () => _confirmDelete(s.id, s.name),
            ),
          ],
        ),
        onTap: () {
          if (s.url != null) {
            _urlController.text = s.url!;
          }
        },
      ),
    );
  }

  void _confirmDelete(String id, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除音源'),
        content: Text('确定要删除「$name」吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await ref.read(databaseProvider).deleteSource(id);
              ref.invalidate(sourceListProvider);
              if (mounted) Navigator.pop(ctx);
              _showSnack('已删除音源', isError: false);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  Future<void> _checkUpdates() async {
    final sources = await ref.read(databaseProvider).getAllSources();
    final withUrl = sources.where((s) => s.url != null).toList();
    if (withUrl.isEmpty) {
      _showSnack('没有可检查更新的音源', isError: false);
      return;
    }

    setState(() => _loading = true);
    int updateCount = 0;
    for (final s in withUrl) {
      try {
        final response = await Dio().get<String>(s.url!);
        if (response.statusCode == 200) {
          final newMeta = SourceMeta.fromScript(response.data ?? '');
          if (newMeta.isValid && newMeta.version != s.version) {
            updateCount++;
          }
        }
      } catch (_) {}
    }
    setState(() => _loading = false);
    _showSnack(
      updateCount > 0 ? '发现 $updateCount 个音源有更新' : '所有音源已是最新',
      isError: false,
    );
  }
}
