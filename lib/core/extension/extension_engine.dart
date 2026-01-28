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
  bool get isExpired => DateTime.now().difference(createdAt).inMinutes > 30;
}

@singleton
class ExtensionEngine {
  final PackStore packStore;
  final ApiKeyStore apiKeyStore;
  final LoggerStore? logger;

  /// JS 运行时缓存：packId -> CachedRuntime
  final Map<String, _CachedRuntime> _runtimeCache = <String, _CachedRuntime>{};

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      headers: <String, dynamic>{
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
    required Map<String, dynamic> params,
    CancelToken? cancelToken,
  }) async {
    // ============================
    // 注入 API Keys（从 params 获取）
    // ============================
    final apiKeysMap = (params['apiKeys'] as Map<String, dynamic>?) ?? <String, dynamic>{};

    final mergedParams = <String, dynamic>{
      ...params,
      ...apiKeysMap, // 展开注入
    };
    // 移除 apiKeys 键避免重复
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
        details: 'id=${pack.id} entry=${pack.entry} domains=${pack.domains.join(",")}',
      );

      // ============================
      // 获取或创建缓存的 JS 运行时
      // ============================
      final rt = await _getOrCreateRuntime(packId, pack);

      // ============================
      // buildRequests(params)
      // ============================
      final dynamic rawReq =
          rt.callJson('buildRequests', <dynamic>[mergedParams]);

      final List<ExtensionRequestSpec> requests =
          _parseRequests(rawReq);

      logger?.d(
        'ExtensionEngine',
        'buildRequests ok',
        details: 'count=${requests.length}',
      );

      final List<ExtensionResponsePayload> responses = [];

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
          details: 'status=${resp.statusCode} len=${resp.body.length}',
        );

        responses.add(resp);
      }

      // ============================
      // parseList(params, responses)
      // ============================
      final dynamic rawList = rt.callJson(
        'parseList',
        <dynamic>[
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
        return const <UniWallpaper>[];
      }

      final out = rawList
          .whereType<Map>()
          .map((m) => UniWallpaper.fromMap(m.cast<String, dynamic>()))
          .where((w) => w.thumbUrl.isNotEmpty || w.fullUrl.isNotEmpty)
          .toList(growable: false);

      logger?.i(
        'ExtensionEngine',
        'parseList ok',
        details: 'count=${out.length}',
      );

      return out;
    } on DioException catch (e, st) {
      // 取消请求不算错误
      if (e.type == DioExceptionType.cancel) {
        logger?.d('ExtensionEngine', 'Request cancelled');
        return const <UniWallpaper>[];
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
      throw AppException.unknown('ExtensionEngine 执行失败: $e', error: e);
    }
  }

  // =====================================================
  // JS 运行时缓存管理
  // =====================================================

  /// 获取或创建缓存的 JS 运行时
  Future<_JsHost> _getOrCreateRuntime(String packId, EnginePack pack) async {
    final cached = _runtimeCache[packId];
    
    // 检查缓存是否有效
    if (cached != null && 
        cached.packVersion == pack.version && 
        !cached.isExpired) {
      logger?.d(
        'ExtensionEngine',
        'Using cached JS runtime',
        details: 'packId=$packId version=${pack.version}',
      );
      return cached.runtime;
    }

    // 清理旧缓存
    if (cached != null) {
      cached.runtime.dispose();
      _runtimeCache.remove(packId);
      logger?.d(
        'ExtensionEngine',
        'Cleared expired JS runtime cache',
        details: 'packId=$packId',
      );
    }

    // 创建新运行时
    final File entryFile = await packStore.resolveEntry(packId, pack.entry);
    final String jsSource = await entryFile.readAsString();

    final rt = _JsHost(logger: logger);
    rt.load(jsSource, sourceUrl: pack.entry);

    // 缓存运行时
    _runtimeCache[packId] = _CachedRuntime(
      runtime: rt,
      packVersion: pack.version,
      createdAt: DateTime.now(),
    );

    logger?.d(
      'ExtensionEngine',
      'Created and cached JS runtime',
      details: 'packId=$packId version=${pack.version}',
    );

    return rt;
  }

  /// 清除指定 pack 的运行时缓存
  void clearRuntimeCache(String packId) {
    final cached = _runtimeCache.remove(packId);
    if (cached != null) {
      cached.runtime.dispose();
      logger?.d('ExtensionEngine', 'Cleared runtime cache', details: 'packId=$packId');
    }
  }

  /// 清除所有运行时缓存
  void clearAllRuntimeCache() {
    for (final entry in _runtimeCache.entries) {
      entry.value.runtime.dispose();
    }
    _runtimeCache.clear();
    logger?.d('ExtensionEngine', 'Cleared all runtime cache');
  }

  // =====================================================

  Future<EnginePack> _getPack(String packId) async {
    final packs = await packStore.list();
    return packs.firstWhere(
      (p) => p.id == packId,
      orElse: () => throw AppException.packNotFound(packId),
    );
  }

  List<ExtensionRequestSpec> _parseRequests(dynamic raw) {
    if (raw is! List) {
      throw AppException.parseError(
        'buildRequests 必须返回数组',
        details: '实际类型: ${raw.runtimeType}',
      );
    }
    return raw
        .whereType<Map>()
        .map((m) => ExtensionRequestSpec.fromMap(m.cast<String, dynamic>()))
        .toList(growable: false);
  }

  void _assertDomainAllowed(EnginePack pack, String url) {
    if (pack.domains.isEmpty) return;

    final host = Uri.parse(url).host;
    final ok = pack.domains.any((d) => host == d || host.endsWith('.$d'));
    if (!ok) {
      throw AppException.domainNotAllowed(host, pack.domains);
    }
  }

  Future<ExtensionResponsePayload> _doRequest(
    ExtensionRequestSpec req, {
    CancelToken? cancelToken,
  }) async {
    final method = req.method.toUpperCase();

    final options = Options(
      method: method,
      responseType: ResponseType.plain,
      headers: req.headers,
      validateStatus: (_) => true,
    );

    late Response<String> r;

    if (method == 'POST') {
      r = await _dio.post<String>(
        req.url,
        data: req.body,
        options: options,
        cancelToken: cancelToken,
      );
    } else {
      r = await _dio.get<String>(
        req.url,
        options: options,
        cancelToken: cancelToken,
      );
    }

    return ExtensionResponsePayload(
      statusCode: r.statusCode ?? 0,
      body: r.data ?? '',
    );
  }

  /// 释放资源
  void dispose() {
    // 清理所有缓存的 JS 运行时
    clearAllRuntimeCache();
    _dio.close();
    logger?.d('ExtensionEngine', 'disposed');
  }
}

// =====================================================

class _JsHost {
  final LoggerStore? logger;
  late final JavascriptRuntime _rt;
  bool _disposed = false;

  _JsHost({this.logger}) {
    _rt = getJavascriptRuntime();
  }

  void load(String jsCode, {required String sourceUrl}) {
    if (_disposed) {
      throw StateError('JsHost has been disposed');
    }
    final r = _rt.evaluate(jsCode, sourceUrl: sourceUrl);
    if (r.isError) {
      logger?.e('JsHost', 'JS load failed', details: r.stringResult);
      throw Exception('JS load failed: ${r.stringResult}');
    }
    logger?.d('JsHost', 'JS loaded', details: sourceUrl);
  }

  dynamic callJson(String fnName, List<dynamic> args) {
    if (_disposed) {
      throw StateError('JsHost has been disposed');
    }
    final argStr = jsonEncode(args);

    final code = """
(() => {
  const args = $argStr;
  if (typeof $fnName !== 'function') {
    throw new Error('Function not found: $fnName');
  }
  const out = $fnName.apply(null, args);
  return JSON.stringify(out);
})()
""";

    final r = _rt.evaluate(code, sourceUrl: 'call_$fnName.js');

    if (r.isError) {
      logger?.e('JsHost', 'JS call failed: $fnName', details: r.stringResult);
      throw Exception('JS call failed: ${r.stringResult}');
    }

    final s = r.stringResult;
    if (s.isEmpty) return null;

    return jsonDecode(s);
  }

  /// 释放 JS 运行时资源
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    // flutter_js 的 JavascriptRuntime 没有 dispose 方法
    // 但我们标记为已释放以防止后续使用
    logger?.d('JsHost', 'disposed');
  }
}