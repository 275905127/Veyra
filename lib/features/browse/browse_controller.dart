import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/exceptions/app_exception.dart';
import '../../core/models/source.dart';
import '../../core/models/uni_wallpaper.dart';
import '../../core/services/wallpaper_service.dart';
import '../../core/storage/source_store.dart';

class BrowseController extends ChangeNotifier {
  final WallpaperService wallpaperService;
  final SourceStore sourceStore;

  BrowseController({
    required this.wallpaperService,
    required this.sourceStore,
  });

  final List<UniWallpaper> _items = <UniWallpaper>[];
  List<UniWallpaper> get items => List.unmodifiable(_items);

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  int _page = 1;
  bool _hasMore = true;

  SourceRef? _active;
  SourceRef? get activeSource => _active;

  // ✅ 并发安全：请求 ID
  String? _currentRequestId;

  // ✅ 请求取消 Token
  CancelToken? _cancelToken;

  // =========================
  // ✅ 新增：查询状态（给筛选面板/搜索用）
  // =========================
  String _keyword = '';
  Map<String, dynamic> _filters = <String, dynamic>{};

  String get keyword => _keyword;

  /// 注意：外部拿到的是不可变视图，避免 UI 直接改内部状态
  Map<String, dynamic> get filters => Map.unmodifiable(_filters);

  /// ✅ 由筛选面板/搜索调用：
  /// - 传 keyword / filters 任意一个即可
  /// - 默认立即 refresh
  Future<void> setQuery({
    String? keyword,
    Map<String, dynamic>? filters,
    bool refreshNow = true,
  }) async {
    bool changed = false;

    if (keyword != null) {
      final k = keyword.trim();
      if (k != _keyword) {
        _keyword = k;
        changed = true;
      }
    }

    if (filters != null) {
      // 复制一份，避免外部引用导致内部状态被悄悄改掉
      final f = Map<String, dynamic>.from(filters);
      // 简单比较：长度或 key/value 变化即视为变更
      if (!_mapEquals(_filters, f)) {
        _filters = f;
        changed = true;
      }
    }

    if (!changed) return;

    // 切换 query 通常应重刷
    if (refreshNow) {
      await refresh();
    } else {
      notifyListeners();
    }
  }

  /// 可选：提供清空 query 的快捷方法
  Future<void> clearQuery({bool refreshNow = true}) async {
    final had = _keyword.isNotEmpty || _filters.isNotEmpty;
    _keyword = '';
    _filters = <String, dynamic>{};
    if (!had) return;

    if (refreshNow) {
      await refresh();
    } else {
      notifyListeners();
    }
  }

  // =========================

  Future<void> setSource(SourceRef src) async {
    if (_active?.id == src.id) return;
    _active = src;
    wallpaperService.logger?.i(
      'BrowseController',
      'setSource',
      details: 'id=${src.id} type=${src.type.name} ref=${src.ref}',
    );
    await refresh();
  }

  void resetToEmpty() {
    // ✅ 取消正在进行的请求
    _cancelPendingRequest();

    _page = 1;
    _hasMore = true;
    _items.clear();
    _error = null;
    _loading = false;
    _active = null;

    // ✅ 同时清掉 query（避免切源后旧筛选影响新源）
    _keyword = '';
    _filters = <String, dynamic>{};

    notifyListeners();
  }

  Future<void> refresh() async {
    if (_active == null) return;

    // ✅ 取消之前的请求
    _cancelPendingRequest();

    _page = 1;
    _hasMore = true;
    _items.clear();
    _error = null;
    notifyListeners();
    await _load();
  }

  Future<void> loadMore() async {
    if (_loading || _active == null || !_hasMore) return;
    await _load();
  }

  /// 取消正在进行的请求
  void _cancelPendingRequest() {
    if (_cancelToken != null && !_cancelToken!.isCancelled) {
      _cancelToken!.cancel('New request initiated');
      wallpaperService.logger?.d(
        'BrowseController',
        'Cancelled pending request',
      );
    }
    _cancelToken = null;
    _currentRequestId = null;
  }

  Future<void> _load() async {
    final src = _active;
    if (src == null) return;

    // ✅ 生成请求 ID 和取消 Token
    final requestId = DateTime.now().millisecondsSinceEpoch.toString();
    _currentRequestId = requestId;
    _cancelToken = CancelToken();

    final int reqPage = _page;

    try {
      _loading = true;
      notifyListeners();

      // ✅ 关键改动：透传 keyword/filters 和 cancelToken
      final result = await wallpaperService.fetchWallpapers(
        source: src,
        sourceStore: sourceStore,
        page: reqPage,
        keyword: _keyword.isEmpty ? null : _keyword,
        filters: _filters.isEmpty ? null : _filters,
        cancelToken: _cancelToken,
      );

      // ✅ 检查请求是否已过期
      if (_currentRequestId != requestId) {
        wallpaperService.logger?.d(
          'BrowseController',
          'request outdated',
          details: 'requestId=$requestId, current=$_currentRequestId',
        );
        return;
      }

      // 空结果：视为没有更多（避免无限翻页但永远没有变化）
      if (result.isEmpty) {
        _hasMore = false;
        _error = null;
        wallpaperService.logger?.i(
          'BrowseController',
          'load ok (empty)',
          details: 'page=$reqPage total=${_items.length} hasMore=$_hasMore',
        );
        return;
      }

      // 去重：优先用 id；否则用 fullUrl/thumbUrl 兜底
      final existingKeys = _items.map(_keyOf).toSet();
      final List<UniWallpaper> deduped = <UniWallpaper>[];
      for (final w in result) {
        final k = _keyOf(w);
        if (k.isEmpty) continue;
        if (existingKeys.add(k)) deduped.add(w);
      }

      _items.addAll(deduped);

      // 只有实际拿到数据才翻页
      _page = reqPage + 1;

      _error = null;

      wallpaperService.logger?.i(
        'BrowseController',
        'load ok',
        details:
            'page=$reqPage added=${deduped.length}/${result.length} total=${_items.length} nextPage=$_page hasMore=$_hasMore keyword=$_keyword filters=${_filters.toString()}',
      );
    } on AppException catch (e, st) {
      // ✅ 使用友好的错误消息
      _error = e.getUserMessage();
      wallpaperService.logger?.e(
        'BrowseController',
        'load failed (AppException): $e',
        details: st.toString(),
      );
    } on DioException catch (e) {
      // ✅ 取消请求不视为错误
      if (e.type == DioExceptionType.cancel) {
        wallpaperService.logger?.d(
          'BrowseController',
          'Request was cancelled',
        );
        return;
      }
      _error = '网络请求失败';
      wallpaperService.logger?.e(
        'BrowseController',
        'load failed (DioException): $e',
      );
    } catch (e, st) {
      _error = '加载失败: $e';
      wallpaperService.logger?.e(
        'BrowseController',
        'load failed: $e',
        details: st.toString(),
      );
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  String _keyOf(UniWallpaper w) {
    final id = w.id.trim();
    if (id.isNotEmpty) return 'id:$id';
    final fu = w.fullUrl.trim();
    if (fu.isNotEmpty) return 'full:$fu';
    final tu = w.thumbUrl.trim();
    if (tu.isNotEmpty) return 'thumb:$tu';
    return '';
  }

  bool _mapEquals(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (!b.containsKey(e.key)) return false;
      final bv = b[e.key];
      final av = e.value;
      // 简单对比：基础类型足够用；复杂结构你后续可换成 deep equals
      if (av is List && bv is List) {
        if (av.length != bv.length) return false;
        for (int i = 0; i < av.length; i++) {
          if (av[i] != bv[i]) return false;
        }
      } else if (av != bv) {
        return false;
      }
    }
    return true;
  }

  @override
  void dispose() {
    // ✅ 释放时取消所有请求
    _cancelPendingRequest();
    super.dispose();
  }
}