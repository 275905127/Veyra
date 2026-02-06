import 'dart:convert';
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

class _CachedRuntime {
  final _JsHost runtime;
  final String packVersion;
  final DateTime createdAt;

  _CachedRuntime({
    required this.runtime,
    required this.packVersion,
    required this.createdAt,
  });

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
      final runtime = await _getOrCreateRuntime(packId, pack);

      final dynamic rawReq =
          runtime.callJson('buildRequests', [mergedParams]);
      final List requests = _parseRequests(rawReq);

      final List responses = [];
      for (final req in requests) {
        final resp = await _doRequest(req, cancelToken: cancelToken);
        responses.add(resp);
      }

      final dynamic rawList = runtime.callJson(
        'parseList',
        [
          mergedParams,
          responses.map((e) => e.toMap()).toList(),
        ],
      );

      if (rawList is! List) return const [];

      final out = rawList
          .whereType<Map>()
          .map((m) => UniWallpaper.fromMap(m.cast()))
          .where((w) =>
              (w.thumbUrl ?? '').isNotEmpty ||
              w.imageUrl.isNotEmpty)
          .toList(growable: false);

      return out;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        return const [];
      }
      throw AppException.network(
        '网络请求失败',
        details: e.message,
        error: e,
      );
    } catch (e) {
      throw AppException.unknown(
        'ExtensionEngine 执行失败: $e',
        error: e,
      );
    }
  }

  Future<_JsHost> _createRuntime(EnginePack pack) async {
    final source = await packStore.loadPackSource(pack.id);
    final engineJs = source.readAsStringSync();
    final rt = getJsRuntime();
    rt.evaluate("""
      try {
        $engineJs
      } catch(e) {
        console.error(e);
      }
    """);
    return _JsHost(runtime: rt, entry: pack.entry);
  }

  Future<_JsHost> _getOrCreateRuntime(String packId, EnginePack pack) async {
    final cached = _runtimeCache[packId];
    if (cached != null && !cached.isExpired) {
      return cached.runtime;
    }

    final host = await _createRuntime(pack);
    _runtimeCache[packId] = _CachedRuntime(
      runtime: host,
      packVersion: pack.version,
      createdAt: DateTime.now(),
    );
    return host;
  }

  List<_ExtRequest> _parseRequests(dynamic rawReq) {
    final list = <_ExtRequest>[];
    if (rawReq is! List) return list;

    for (final item in rawReq) {
      if (item is! Map) continue;
      final url = item['url'].toString();
      final method = (item['method'] ?? 'GET').toString();
      list.add(_ExtRequest(url: url, method: method, data: item));
    }
    return list;
  }

  Future<ResponseBody> _doRequest(_ExtRequest req,
      {CancelToken? cancelToken}) {
    return _dio.request(
      req.url,
      data: req.data,
      cancelToken: cancelToken,
    ).then((r) => ResponseBody.fromString(
          r.data.toString(),
          r.statusCode ?? 500,
          headers: const {},
        ));
  }

  Future<EnginePack> _getPack(String id) => packStore.loadPack(id);
}

class _ExtRequest {
  final String url;
  final String method;
  final Map data;

  _ExtRequest({
    required this.url,
    required this.method,
    required this.data,
  });
}