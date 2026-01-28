import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';

import '../../core/models/source.dart';
import '../../core/storage/pack_store.dart';
import '../../core/storage/source_store.dart';

@singleton
class SourceController extends ChangeNotifier {
  final SourceStore sourceStore;
  final PackStore packStore;

  SourceController({
    required this.sourceStore,
    required this.packStore,
  }) {
    sourceStore.addListener(_onSourceStoreChanged);
  }

  final List<SourceRef> _sources = <SourceRef>[];
  List<SourceRef> get sources => List.unmodifiable(_sources);

  bool _disposed = false;

  Future<void> load() async {
    try {
      final list = await sourceStore.listRefs();
      _sources
        ..clear()
        ..addAll(list);
      if (!_disposed) notifyListeners();
    } catch (e) {
      _sources.clear();
      if (!_disposed) notifyListeners();
    }
  }

  /// ✅ 新增：级联删除图源和对应的引擎包
  Future<void> deleteSource(String sourceId) async {
    try {
      // 1. 获取图源配置，找到对应的 packId
      final spec = await sourceStore.getSpecRaw(sourceId);
      final packId = (spec['packId'] ?? spec['pack'] ?? '').toString();

      // 2. 从图源列表移除配置
      await sourceStore.remove(sourceId);

      // 3. 如果有 packId，卸载对应的引擎包文件
      if (packId.isNotEmpty) {
        await packStore.uninstall(packId);
      }

      // 4. 刷新列表
      await load();
    } catch (e) {
      debugPrint('Delete source failed: $e');
      rethrow;
    }
  }

  void _onSourceStoreChanged() {
    if (_disposed) return;
    load();
  }

  @override
  void dispose() {
    _disposed = true;
    sourceStore.removeListener(_onSourceStoreChanged);
    super.dispose();
  }
}
