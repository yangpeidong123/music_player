import 'dart:convert';
import 'package:dio/dio.dart';
import '../engine/source_engine.dart';
import '../engine/source_manager.dart';
import 'database.dart';

/// 音源持久化管理
class SourceStorage {
  final AppDatabase _db;
  final SourceManager _manager;
  final Dio _dio;

  SourceStorage(this._db, this._manager) : _dio = Dio();

  /// 保存音源到数据库
  Future<String> save({required String script, String? url}) async {
    final meta = SourceMeta.fromScript(script);
    final id = url ?? 'src_${DateTime.now().millisecondsSinceEpoch}';

    // 先加载测试
    final engine = SourceEngine();
    final success = await engine.loadFromScript(script);
    if (!success) throw Exception('音源加载失败');
    engine.dispose();

    await _db.saveSource(
      id: id, name: meta.name, url: url, script: script,
      version: meta.version, author: meta.author, homepage: meta.homepage,
      capabilities: jsonEncode({
        'sources': engine.capabilities?.sources ?? {},
        'qualitys': engine.capabilities?.qualitys ?? {},
      }),
    );
    return id;
  }

  /// 从 URL 下载并保存
  Future<String> downloadAndSave(String url) async {
    final response = await _dio.get<String>(url);
    if (response.statusCode != 200) {
      throw Exception('下载失败: HTTP ${response.statusCode}');
    }
    return save(script: response.data!, url: url);
  }

  Future<void> delete(String id) async => await _db.deleteSource(id);
  Future<void> setEnabled(String id, bool enabled) async => await _db.setSourceEnabled(id, enabled);

  Future<bool> checkUpdate(String id) async {
    final sources = await _db.getAllSources();
    final source = sources.firstWhere((s) => s.id == id);
    if (source.url == null) return false;
    try {
      final response = await _dio.get<String>(source.url!);
      if (response.statusCode != 200) return false;
      final newMeta = SourceMeta.fromScript(response.data!);
      return newMeta.version != source.version;
    } catch (_) {
      return false;
    }
  }
}
