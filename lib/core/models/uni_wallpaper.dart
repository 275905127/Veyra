import 'package:flutter/foundation.dart';

@immutable
class UniWallpaper {
  // -----------------
  // 基础必需字段
  // -----------------
  final String id;
  final String imageUrl;

  // -----------------
  // 预览相关
  // -----------------
  final String? thumbUrl;

  // -----------------
  // 显示信息
  // -----------------
  final String? title;        // 标题
  final String? author;       // 作者 / 上传者
  final String? sourceId;     // 引擎ID
  final String? sourceName;   // 显示名称

  // -----------------
  // 图片属性
  // -----------------
  final int? width;
  final int? height;
  final int? size;            // bytes

  // -----------------
  // 分类信息
  // -----------------
  final List<String>? tags;

  const UniWallpaper({
    required this.id,
    required this.imageUrl,
    this.thumbUrl,
    this.title,
    this.author,
    this.sourceId,
    this.sourceName,
    this.width,
    this.height,
    this.size,
    this.tags,
  });
}