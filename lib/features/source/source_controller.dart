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
    // SourceStore 变化时（active 或 sources 更新），同步刷新 sources 列表
    sourceStore.addListener(_onSourceStoreChanged);
  }

  final List<SourceRef> _sources = <SourceRef>[];
  List<SourceRef> get sources => List.unmodifiable(_sources);

  bool _disposed = false;

  /// 从持久化仓库加载图源列表
  Future<void> load() async {
    try {
      final list = await sourceStore.listRefs();
      _sources
        ..clear()
        ..addAll(list);
      if (!_disposed) notifyListeners();
    } catch (e) {
      // 这里不抛异常，避免 UI 崩；需要的话后续接 LoggerStore
      _sources.clear();
      if (!_disposed) notifyListeners();
    }
  }

  void _onSourceStoreChanged() {
    // 避免在 dispose 后触发
    if (_disposed) return;
    // 触发一次异步刷新即可
    load();
  }

  @override
  void dispose() {
    _disposed = true;
    sourceStore.removeListener(_onSourceStoreChanged);
    super.dispose();
  }
}