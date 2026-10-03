import 'dart:async';
import 'source_engine.dart';

/// 音源管理器 — 管理多个已加载的音源
class SourceManager {
  final _engines = <String, SourceEngine>{}; // id -> engine
  final _metas = <String, SourceMeta>{};
  final _capabilities = <String, SourceCapabilities>{};
  String? _activeSourceId;

  /// 已加载的音源列表
  List<SourceMeta> get sources => _metas.values.toList();

  /// 当前活跃音源
  SourceEngine? get activeEngine =>
      _activeSourceId != null ? _engines[_activeSourceId] : null;

  /// 当前活跃音源 id（供 Provider 层同步用）
  String? get activeId => _activeSourceId;

  /// 添加音源
  Future<String> addSource(String script, {String? id}) async {
    final sourceId = id ?? DateTime.now().millisecondsSinceEpoch.toString();
    final engine = SourceEngine();
    bool success = false;
    try {
      success = await engine.loadFromScript(script);
    } catch (e) {
      engine.dispose();
      rethrow;
    }

    if (success) {
      // 重复导入同一 id 时先释放旧引擎，避免旧 QuickJS 运行时泄漏
      _engines[sourceId]?.dispose();
      _engines[sourceId] = engine;
      _metas[sourceId] = engine.meta!;
      final caps = engine.capabilities;
      if (caps != null) {
        _capabilities[sourceId] = caps;
      }
      if (_activeSourceId == null) {
        _activeSourceId = sourceId;
      }
      print('[SourceManager] 音源已添加: ${engine.meta!.name} (id=$sourceId)');
    } else {
      engine.dispose();
      throw Exception('音源加载失败');
    }
    return sourceId;
  }

  /// 从 URL 添加音源
  Future<String> addSourceFromUrl(String url) async {
    final engine = SourceEngine();
    final success = await engine.loadFromUrl(url);
    if (!success) {
      engine.dispose();
      throw Exception('音源加载失败: $url');
    }
    final sourceId = DateTime.now().millisecondsSinceEpoch.toString();
    _engines[sourceId] = engine;
    _metas[sourceId] = engine.meta!;
    final caps = engine.capabilities;
    if (caps != null) {
      _capabilities[sourceId] = caps;
    }
    if (_activeSourceId == null) {
      _activeSourceId = sourceId;
    }
    return sourceId;
  }

  /// 切换活跃音源（返回是否成功：仅已加载的音源可激活）
  bool setActiveSource(String id) {
    if (_engines.containsKey(id)) {
      _activeSourceId = id;
      return true;
    }
    return false;
  }

  /// 移除音源
  void removeSource(String id) {
    _engines[id]?.dispose();
    _engines.remove(id);
    _metas.remove(id);
    _capabilities.remove(id);
    if (_activeSourceId == id) {
      _activeSourceId = _engines.keys.isNotEmpty ? _engines.keys.first : null;
    }
  }

  /// 获取指定音源的所有可用平台
  List<String> getAvailablePlatforms(String sourceId) {
    return _capabilities[sourceId]?.sources.keys.toList() ?? [];
  }

  /// 获取指定平台的可用音质
  List<String> getAvailableQualitys(String sourceId, String platform) {
    return _capabilities[sourceId]?.qualitys[platform] ?? [];
  }

  /// 释放所有资源
  void dispose() {
    for (final engine in _engines.values) {
      engine.dispose();
    }
    _engines.clear();
  }
}
