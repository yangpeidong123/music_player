import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../shared/providers/providers.dart';

class SourceManagerPage extends ConsumerStatefulWidget {
  const SourceManagerPage({super.key});

  @override
  ConsumerState<SourceManagerPage> createState() => _SourceManagerPageState();
}

class _SourceManagerPageState extends ConsumerState<SourceManagerPage> {
  final _urlController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _importFromUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() => _loading = true);
    try {
      final storage = ref.read(sourceStorageProvider);
      final manager = ref.read(sourceManagerProvider);

      // 下载音源脚本
      await storage.downloadAndSave(url);
      // 重新加载音源列表
      ref.invalidate(sourceListProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('音源导入成功！'), backgroundColor: Colors.green),
        );
        _urlController.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _checkUpdates() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('正在检查更新...')),
    );
    final storage = ref.read(sourceStorageProvider);
    final sources = await ref.read(databaseProvider).getAllSources();
    int updateCount = 0;
    for (final s in sources) {
      if (await storage.checkUpdate(s.id)) updateCount++;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(updateCount > 0 ? '发现 $updateCount 个音源有更新' : '所有音源已是最新')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sourcesAsync = ref.watch(sourceListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('音源管理'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _checkUpdates),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 导入区域
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('导入音源', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      labelText: '音源 URL',
                      hintText: 'https://example.com/source.js',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.link),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: _loading ? null : _importFromUrl,
                        icon: _loading
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.download),
                        label: Text(_loading ? '导入中...' : '从 URL 导入'),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('文件导入功能开发中')),
                          );
                        },
                        icon: const Icon(Icons.upload_file),
                        label: const Text('从文件导入'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          // 已导入音源列表
          sourcesAsync.when(
            data: (sources) {
              if (sources.isEmpty) {
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text('尚未导入音源'),
                    subtitle: const Text('导入洛雪音源后即可搜索和播放音乐'),
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('已导入 (${sources.length})', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  ...sources.map((s) => Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: s.enabled
                                ? Theme.of(context).colorScheme.primaryContainer
                                : Colors.grey.shade300,
                            child: Icon(Icons.source, color: s.enabled ? null : Colors.grey),
                          ),
                          title: Text(s.name),
                          subtitle: Text('v${s.version} · by ${s.author}${s.url != null ? ' · ${s.url}' : ''}'),
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
                                onPressed: () async {
                                  final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('删除音源'),
                                      content: Text('确定要删除「${s.name}」吗？'),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
                                        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
                                      ],
                                    ),
                                  );
                                  if (confirmed == true) {
                                    await ref.read(databaseProvider).deleteSource(s.id);
                                    ref.invalidate(sourceListProvider);
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      )),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Card(child: ListTile(title: Text('加载失败: $err'))),
          ),
          const SizedBox(height: 24),
          // 帮助说明
          Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
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
                    '你可以在网上搜索「洛雪音源」获取可用的音源 URL，粘贴到上方导入。\n\n'
                    '注意：本项目不内置任何音源，音源由用户自行导入，仅供个人学习使用。',
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
}
