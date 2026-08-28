import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../core/engine/source_engine.dart';
import '../../shared/providers/providers.dart';
import '../../shared/widgets/mini_player_bar.dart';

class SourceManagerPage extends ConsumerStatefulWidget {
  const SourceManagerPage({super.key});
  @override
  ConsumerState<SourceManagerPage> createState() => _SourceManagerPageState();
}

class _SourceManagerPageState extends ConsumerState<SourceManagerPage> {
  final _urlController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() { _urlController.dispose(); super.dispose(); }

  Future<void> _importFromUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    setState(() => _loading = true);
    try {
      final dio = Dio();
      final response = await dio.get<String>(url);
      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');

      final script = response.data!;
      final meta = SourceMeta.fromScript(script);

      // 验证可加载
      final engine = SourceEngine();
      final success = await engine.loadFromScript(script);
      engine.dispose();
      if (!success) throw Exception('音源脚本执行失败');

      // 保存到数据库
      final id = url;
      final manager = ref.read(sourceManagerProvider);
      await ref.read(databaseProvider).saveSource(
        id: id, name: meta.name, url: url, script: script,
        version: meta.version, author: meta.author, homepage: meta.homepage,
        capabilities: '{}',
      );

      // 立即加载到运行时
      await manager.addSource(script, id: id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('音源导入成功！'), backgroundColor: Colors.green),
        );
        _urlController.clear();
        ref.invalidate(sourceListProvider);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sourcesAsync = ref.watch(sourceListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('音源管理')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
                  Row(children: [
                    FilledButton.icon(
                      onPressed: _loading ? null : _importFromUrl,
                      icon: _loading
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.download),
                      label: Text(_loading ? '导入中...' : '从 URL 导入'),
                    ),
                  ]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          sourcesAsync.when(
            data: (sources) {
              if (sources.isEmpty) {
                return Card(child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('尚未导入音源'),
                  subtitle: const Text('导入洛雪音源后即可搜索和播放音乐'),
                ));
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
                      subtitle: Text('v${s.version} · by ${s.author}'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
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
                            final ok = await showDialog<bool>(
                              context: context, builder: (_) => AlertDialog(
                                title: const Text('删除音源'),
                                content: Text('确定要删除「${s.name}」吗？'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
                                  FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
                                ],
                              ),
                            );
                            if (ok == true) {
                              await ref.read(databaseProvider).deleteSource(s.id);
                              ref.invalidate(sourceListProvider);
                            }
                          },
                        ),
                      ]),
                    ),
                  )),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Card(child: ListTile(title: Text('加载失败: $err'))),
          ),
          const SizedBox(height: 24),
          Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Icon(Icons.help_outline), SizedBox(width: 8), Text('什么是音源？', style: TextStyle(fontWeight: FontWeight.bold))]),
                SizedBox(height: 8),
                Text('音源是洛雪音乐格式的 JS 脚本，提供各大音乐平台的搜索和播放能力。\n\n你可以在网上搜索「洛雪音源」获取可用的音源 URL，粘贴到上方导入。\n\n注意：本项目不内置任何音源，音源由用户自行导入，仅供个人学习使用。', style: TextStyle(height: 1.5)),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
