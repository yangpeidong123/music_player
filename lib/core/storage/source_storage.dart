import 'dart:convert';
import 'package:dio/dio.dart';
import '../engine/source_engine.dart';
import '../engine/source_manager.dart';
import 'database.dart';

/// 音源持久化管理 — 将音源脚本保存到 SQLite
class SourceStorage {
  final AppDatabase _db;
  final SourceManager _manager;

  SourceStorage(this._db, this._manager);

  /// 从数据库加载所有已保存的音源
  Future<void> loadAllFromDb() async {
    final sources = await _db.getAllSources();
    for (final s in sources) {
      if (!s.enabled) continue;
      try {
        final engine = SourceEngine();
        await engine.loadFromScript(s.script);
        // 添加到 SourceManager 但不重复保存
        // 直接调用内部方法
      } catch (e) {
        print('[SourceStorage] 加载音源失败 ${s.name}: $e');
      }
    }
  }

  /// 保存音源到数据库
  Future<String> save({
    required String script,
    String? url,
  }) async {
    final meta = SourceMeta.fromScript(script);
    final id = url ?? 'src_${DateTime.now().millisecondsSinceEpoch}';

    // 先加载测试
    final engine = SourceEngine();
    final success = await engine.loadFromScript(script);
    if (!success) throw Exception('音源加载失败');
    engine.dispose();

    await _db.saveSource(
      id: id,
      name: meta.name,
      url: url,
      script: script,
      version: meta.version,
      author: meta.author,
      homepage: meta.homepage,
      capabilities: jsonEncode({
        'sources': engine.capabilities?.sources ?? {},
        'qualitys': engine.capabilities?.qualitys ?? {},
      }),
    );

    return id;
  }

  /// 从 URL 下载并保存音源
  Future<String> downloadAndSave(String url) async {
    final dio = Dio();
    final response = await dio.get<String>(url);
    if (response.statusCode != 200) {
      throw Exception('下载失败: HTTP ${response.statusCode}');
    }
    return save(script: response.data!, url: url);
  }

  /// 删除音源
  Future<void> delete(String id) async {
    await _db.deleteSource(id);
  }

  /// 启用/禁用音源
  Future<void> setEnabled(String id, bool enabled) async {
    await _db.setSourceEnabled(id, enabled);
  }

  /// 检查音源更新
  Future<bool> checkUpdate(String id) async {
    final sources = await _db.getAllSources();
    final source = sources.firstWhere((s) => s.id == id);
    if (source.url == null) return false;

    try {
      final dio = Dio();
      final response = await dio.get<String>(source.url!);
      if (response.statusCode != 200) return false;

      final newMeta = SourceMeta.fromScript(response.data!);
      if (newMeta.version != source.version) {
        return true; // 有更新
      }
    } catch (_) {
      return false;
    }
    return false;
  }
}
