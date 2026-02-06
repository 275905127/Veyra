import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:injectable/injectable.dart';

import '../exceptions/app_exception.dart';
import '../log/logger_store.dart';
import '../models/engine_pack.dart';
import '../models/uni_wallpaper.dart';
import '../storage/pack_store.dart';
import '../storage/api_key_store.dart';
import 'extension_protocol.dart';

/// JS 运行时缓存条目
class _CachedRuntime {
  final _JsHost runtime;
  final String packVersion;
  final DateTime createdAt;

  _CachedRuntime({
    required this.runtime,
    required this.packVersion,
    required this.createdAt,
  });

  /// 缓存是否过期（超过 30 分钟）
  bool get isExpired =>
      DateTime.now().difference(createdAt).inMinutes > 30;
}

@singleton
class ExtensionEngine {
  final PackStore packStore;
  final ApiKeyStore apiKeyStore;
  final LoggerStore? logger;

  final Map<String, _CachedRuntime> _runtimeCache = {};

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36',
        'Accept': '*/*',
      },
    ),
  );

  ExtensionEngine({
    required this.packStore,
    required this.apiKeyStore,
    this.logger,
  });

  Future<List<UniWallpaper>> fetchFromExtension({
    required String packId,
    required Map params,
    CancelToken? cancelToken,
  }) async {
    final apiKeysMap = (params['apiKeys'] as Map?) ?? {};
    final mergedParams = {...params, ...apiKeysMap};
    mergedParams.remove('apiKeys');

    logger?.i(
      'ExtensionEngine',
      'fetchFromExtension',
      details: 'packId=$packId params=${jsonEncode(mergedParams)}',
    );

    try {
      final EnginePack pack = await _getPack(packId);
      logger?.d(
        'ExtensionEngine',
        'pack loaded',
        details:
            'id=${pack.id} entry=${pack.entry} domains=${pack.domains.join(",")}',
      );

      final rt = await _getOrCreateRuntime(packId, pack);

      final dynamic rawReq =
          rt.callJson('buildRequests', [mergedParams]);
      final List requests = _parseRequests(rawReq);
      logger?.d(
        'ExtensionEngine',
        'buildRequests ok',
        details: 'count=${requests.length}',
      );

      final List responses = [];
      for (final req in requests) {
        _assertDomainAllowed(pack, req.url);
        logger?.d(
          'ExtensionEngine',
          'request',
          details: '${req.method} ${req.url}',
        );

        final resp = await _doRequest(req, cancelToken: cancelToken);
        logger?.d(
          'ExtensionEngine',
          'response',
          details:
              'status=${resp.statusCode} len=${resp.body.length}',
        );
        responses.add(resp);
      }

      final dynamic rawList = rt.callJson(
        'parseList',
        [
          mergedParams,
          responses.map((e) => e.toMap()).toList(),
        ],
      );

      if (rawList is! List) {
        logger?.w(
          'ExtensionEngine',
          'parseList returned non-list',
          details: 'type=${rawList.runtimeType}',
        );
        return const [];
      }

      final out = rawList
          .whereType<Map>()
          .map((m) => UniWallpaper.fromMap(m.cast()))
          .where((w) =>
              (w.thumbUrl ?? '').isNotEmpty ||
              w.imageUrl.isNotEmpty)
          .toList(growable: false);

      logger?.i(
        'ExtensionEngine',
        'parseList ok',
        details: 'count=${out.length}',
      );

      return out;
    } on DioException catch (e, st) {
      if (e.type == DioExceptionType.cancel) {
        logger?.d('ExtensionEngine', 'Request cancelled');
        return const [];
      }
      logger?.e(
        'ExtensionEngine',
        'Network error: $e',
        details: st.toString(),
      );
      throw AppException.network(
        '网络请求失败',
        details: e.message,
        error: e,
      );
    } catch (e, st) {
      logger?.e(
        'ExtensionEngine',
        'failed: $e',
        details: st.toString(),
      );
      if (e is AppException) {
        rethrow;
      }
      throw AppException.unknown(
        'ExtensionEngine 执行失败: $e',
        error: e,
      );
    }
  }

  // ... 以下逻辑无需变动（runtime cache / _getPack / _doRequest 等）
}