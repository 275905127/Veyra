import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';

import '../engine/rule_engine.dart';
import '../exceptions/app_exception.dart';
import '../extension/extension_engine.dart';
import '../log/logger_store.dart';
import '../models/source.dart';
import '../models/source_spec.dart';
import '../models/uni_wallpaper.dart';
import '../storage/api_key_store.dart';
import '../storage/pack_store.dart';
import '../storage/source_store.dart';

@singleton
class WallpaperService {
  final RuleEngine ruleEngine;
  final PackStore packStore;
  final ExtensionEngine extensionEngine;
  final ApiKeyStore apiKeyStore;
  final LoggerStore? logger;

  WallpaperService({
    required this.ruleEngine,
    required this.packStore,
    required this.extensionEngine,
    required this.apiKeyStore,
    this.logger,
  });

  Map<String, String> get commonImageHeaders => ruleEngine.ctx.commonImageHeaders;

  Future<List<UniWallpaper>> fetchWallpapers({
    required SourceRef source,
    required SourceStore sourceStore,
    required int page,
    String? keyword,
    Map<String, dynamic>? filters,
    CancelToken? cancelToken,
  }) async {
    logger?.i(
      'WallpaperService',
      'fetchWallpapers',
      details:
          'type=${source.type.name} id=${source.id} ref=${source.ref} page=$page keyword=${keyword ?? ""}',
    );

    try {
      switch (source.type) {
        case SourceType.rule:
          logger?.d('WallpaperService', 'route=rule', details: 'specRef=${source.ref}');
          final raw = await sourceStore.getSpecRaw(source.ref);
          final spec = SourceSpec(raw: raw);
          final list = await ruleEngine.fetchByKey(
            engineKey: 'rest_jsonpath_v1',
            spec: spec,
            page: page,
            keyword: keyword,
            filters: filters,
          );
          logger?.i('WallpaperService', 'rule ok', details: 'count=${list.length}');
          return list;

        case SourceType.extension:
          Map<String, dynamic> raw = const <String, dynamic>{};
          try {
            raw = await sourceStore.getSpecRaw(source.id);
          } catch (_) {
            raw = const <String, dynamic>{};
          }

          final packId = ((raw['packId'] ?? raw['pack'] ?? source.ref) ?? '').toString().trim();
          if (packId.isEmpty) {
            throw Exception('extension packId is empty for sourceId=${source.id}');
          }

          // ✅ mode 优先取 filters.mode，其次 raw.defaultMode/raw.mode
          final f = filters ?? <String, dynamic>{};
          final mode = ((f['mode'] ?? raw['defaultMode'] ?? raw['mode']) ?? '').toString().trim();

          logger?.d(
            'WallpaperService',
            'route=extension',
            details: 'packId=$packId mode=$mode sourceId=${source.id}',
          );

          // ✅ 获取图源级的 API Keys
          final apiKeys = await apiKeyStore.getAllKeys(source.id);

          final list = await extensionEngine.fetchFromExtension(
            packId: packId,
            params: <String, dynamic>{
              'page': page,
              'keyword': keyword ?? '',
              'filters': f,
              'mode': mode,
              'sourceId': source.id,
              'apiKeys': apiKeys, // ✅ 传入 API Keys
            },
            cancelToken: cancelToken,
          );
          logger?.i('WallpaperService', 'extension ok', details: 'count=${list.length}');
          return list;

        case SourceType.dedicated:
          throw Exception('Dedicated source not wired yet.');
      }
    } on DioException catch (e) {
      // 取消请求不视为错误，直接返回空列表
      if (e.type == DioExceptionType.cancel) {
        logger?.d('WallpaperService', 'Request cancelled');
        return const <UniWallpaper>[];
      }
      logger?.e('WallpaperService', 'Network error: $e');
      throw AppException.network('网络请求失败', details: e.message, error: e);
    } catch (e, st) {
      logger?.e('WallpaperService', 'failed: $e', details: st.toString());
      if (e is AppException) {
        rethrow;
      }
      throw AppException.unknown('获取壁纸失败: $e', error: e);
    }
  }

  /// 释放资源
  void dispose() {
    extensionEngine.dispose();
    logger?.d('WallpaperService', 'disposed');
  }
}