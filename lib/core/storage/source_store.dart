import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/source.dart';

/// SourceStore：图源仓库（本地持久化）
///
/// - 保存每个图源的 spec（JSON Map）
/// - 保存图源元信息（name/type/ref）
/// - 维护 active（当前激活图源）
///
/// 注意：这里只做存取与状态维护，不做解析与网络请求。
class SourceStore extends ChangeNotifier {
  static const String _kIds = 'sources.ids'; // JSON List<String>
  static const String _kActiveId = 'sources.activeId';

  static String _kSpec(String id) => 'sources.$id.spec'; // JSON Map
  static String _kMeta(String id) => 'sources.$id.meta'; // JSON Map

  SharedPreferences? _sp;

  SourceRef? _active;
  SourceRef? get active => _active;

  /// 必须在 main 里调用一次。
  Future<void> init() async {
    _sp ??= await SharedPreferences.getInstance();

    // 恢复 active（如果存在且 meta 完整）
    final activeId = _sp!.getString(_kActiveId);
    if (activeId != null) {
      final meta = _readMeta(activeId);
      if (meta != null) {
        _active = _metaToSourceRef(activeId, meta);
      } else {
        // meta 丢失则清理 active
        await _sp!.remove(_kActiveId);
        _active = null;
      }
    }
  }

  /// 列出所有图源 id（按保存顺序）
  Future<List<String>> listIds() async {
    final sp = await _ensure();
    final raw = sp.getString(_kIds);
    if (raw == null || raw.isEmpty) return <String>[];
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return decoded.whereType<String>().toList(growable: false);
    }
    return <String>[];
  }

  /// 获取图源 spec 的原始 JSON Map
  Future<Map<String, dynamic>> getSpecRaw(String id) async {
    final sp = await _ensure();
    final raw = sp.getString(_kSpec(id));
    if (raw == null || raw.isEmpty) {
      throw Exception('Source spec not found: $id');
    }
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return decoded.cast<String, dynamic>();
    throw Exception('Invalid source spec: $id');
  }

  /// 写入/更新某个图源 spec（以及 meta）
  ///
  /// name/type/ref 用于 UI 展示与选择；specRaw 用于 RuleEngine/ExtensionEngine 解析。
  Future<void> upsertSpecRaw({
    required String id,
    required Map<String, dynamic> specRaw,
    required String name,
    required SourceType type,
    required String ref,
  }) async {
    final sp = await _ensure();

    // 1) ids 维护
    final ids = (await listIds()).toList(growable: true);
    if (!ids.contains(id)) {
      ids.add(id);
      await sp.setString(_kIds, jsonEncode(ids));
    }

    // 2) spec
    await sp.setString(_kSpec(id), jsonEncode(specRaw));

    // 3) meta
    final meta = <String, dynamic>{
      'name': name,
      'type': type.name,
      'ref': ref,
    };
    await sp.setString(_kMeta(id), jsonEncode(meta));

    // 如果当前 active 正好是它，同步更新显示信息
    if (_active?.id == id) {
      _active = SourceRef(id: id, name: name, type: type, ref: ref);
      notifyListeners();
    }
  }

  /// 删除一个图源（同时处理 active）
  Future<void> remove(String id) async {
    final sp = await _ensure();

    final ids = (await listIds()).toList(growable: true);
    ids.remove(id);
    await sp.setString(_kIds, jsonEncode(ids));

    await sp.remove(_kSpec(id));
    await sp.remove(_kMeta(id));

    if (_active?.id == id) {
      _active = null;
      await sp.remove(_kActiveId);
      notifyListeners();
    }
  }

  /// 读取所有图源的 SourceRef（供 SourceController 使用）
  Future<List<SourceRef>> listRefs() async {
    final ids = await listIds();
    final out = <SourceRef>[];
    for (final id in ids) {
      final meta = _readMeta(id);
      if (meta == null) continue;
      out.add(_metaToSourceRef(id, meta));
    }
    return out;
  }

  /// 设置 active（支持传 null 清空）
  Future<void> setActive(SourceRef? src) async {
    final sp = await _ensure();

    if (src == null) {
      _active = null;
      await sp.remove(_kActiveId);
      notifyListeners();
      return;
    }

    // 确保 meta 存在（如果外部传入的是临时对象，也能被恢复）
    final meta = <String, dynamic>{
      'name': src.name,
      'type': src.type.name,
      'ref': src.ref,
    };
    await sp.setString(_kMeta(src.id), jsonEncode(meta));

    _active = src;
    await sp.setString(_kActiveId, src.id);

    debugPrint('[SourceStore] active => ${src.id} (${src.type.name}) ref=${src.ref}');
    notifyListeners();
  }

  // -------------------------
  // helpers
  // -------------------------

  Future<SharedPreferences> _ensure() async {
    _sp ??= await SharedPreferences.getInstance();
    return _sp!;
  }

  Map<String, dynamic>? _readMeta(String id) {
    final sp = _sp;
    if (sp == null) return null;
    final raw = sp.getString(_kMeta(id));
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return decoded.cast<String, dynamic>();
    return null;
  }

  SourceRef _metaToSourceRef(String id, Map<String, dynamic> meta) {
    final name = (meta['name'] as String?)?.trim();
    final typeStr = (meta['type'] as String?)?.trim();
    final ref = (meta['ref'] as String?)?.trim();

    final type = SourceType.values.firstWhere(
      (e) => e.name == typeStr,
      orElse: () => SourceType.rule,
    );

    return SourceRef(
      id: id,
      name: (name == null || name.isEmpty) ? id : name,
      type: type,
      ref: (ref == null || ref.isEmpty) ? id : ref,
    );
  }
}