import 'package:flutter/foundation.dart';

@immutable
class UniWallpaper {
  // -----------------
  // 基础字段（与你最初架构保持一致）
  // -----------------

  final String id;

  /// 缩略图
  final String thumbUrl;

  /// 原图（核心字段）
  final String fullUrl;

  /// 原图别名（给后续新代码使用）
  String get imageUrl => fullUrl;

  final int width;
  final int height;
  final int grade;

  /// 上传者 / 作者
  final String? uploader;

  /// 标签
  final List<String> tags;

  /// JS 传入的请求头
  final Map<String, String>? headers;

  const UniWallpaper({
    required this.id,
    required this.thumbUrl,
    required this.fullUrl,
    required this.width,
    required this.height,
    this.grade = 0,
    this.uploader,
    this.tags = const [],
    this.headers,
  });

  // -----------------
  // JSON → Model
  // -----------------

  factory UniWallpaper.fromMap(Map<String, dynamic> m) {
    int asInt(dynamic v) =>
        int.tryParse((v ?? 0).toString()) ?? 0;

    List<String> asList(dynamic v) =>
        (v is List)
            ? v
                .map((e) => e.toString())
                .where((e) => e.isNotEmpty)
                .toList()
            : const <String>[];

    // 解析 headers
    Map<String, String>? headersMap;
    if (m['headers'] is Map) {
      headersMap = Map<String, String>.from(m['headers']);
    }

    final thumb =
        (m['thumbUrl'] ?? m['thumb'] ?? '').toString();

    final full =
        (m['fullUrl'] ??
                m['full'] ??
                m['imageUrl'] ??
                thumb)
            .toString();

    return UniWallpaper(
      id: (m['id'] ?? '').toString(),
      thumbUrl: thumb,
      fullUrl: full,
      width: asInt(m['width']),
      height: asInt(m['height']),
      grade: asInt(m['grade']),
      uploader: ((m['uploader'] ?? '').toString().isEmpty)
          ? null
          : (m['uploader'] ?? '').toString(),
      tags: asList(m['tags']),
      headers: headersMap,
    );
  }
}