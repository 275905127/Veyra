import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/models/uni_wallpaper.dart';

class ViewerPage extends StatelessWidget {
  final UniWallpaper wallpaper;

  const ViewerPage({
    super.key,
    required this.wallpaper,
  });

  /// ✅ 复制过来的动态 Header 生成逻辑
  /// 详情页同样需要 Referer 才能下载大图
  Map<String, String> _getDynamicHeaders(String url) {
    if (url.isEmpty) return const {};
    try {
      final uri = Uri.parse(url);
      final origin = '${uri.scheme}://${uri.host}/';
      return {
        'Referer': origin,
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      };
    } catch (_) {
      return const {};
    }
  }

  @override
  Widget build(BuildContext context) {
    // 优先使用 ID 作为 Hero Tag
    final heroTag = wallpaper.id.isNotEmpty ? wallpaper.id : wallpaper.fullUrl;
    final thumbUrl = wallpaper.thumbUrl.isNotEmpty ? wallpaper.thumbUrl : wallpaper.fullUrl;
    final fullUrl = wallpaper.fullUrl;

    // ✅ 为大图和缩略图生成 Headers
    final fullHeaders = _getDynamicHeaders(fullUrl);
    // 缩略图可能来自不同域名（虽然 Pixiv 通常是一样的），为了保险也算一下
    final thumbHeaders = _getDynamicHeaders(thumbUrl);

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true, // 沉浸式
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.3), // 半透明
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          '${wallpaper.width} × ${wallpaper.height}',
          style: const TextStyle(fontSize: 14),
        ),
        centerTitle: true,
      ),
      body: Center(
        child: Hero(
          tag: heroTag,
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: CachedNetworkImage(
              imageUrl: fullUrl,
              httpHeaders: fullHeaders, // ✅ 传入大图 Headers
              fit: BoxFit.contain,
              // 使用缩略图作为占位，平滑过渡
              placeholder: (c, url) => CachedNetworkImage(
                imageUrl: thumbUrl,
                httpHeaders: thumbHeaders, // ✅ 传入缩略图 Headers
                fit: BoxFit.contain,
                // 缩略图本身还在加载时的占位
                placeholder: (_, __) => const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
                errorWidget: (_, __, ___) => const SizedBox.shrink(),
              ),
              errorWidget: (c, _, error) {
                // 打印错误方便调试
                debugPrint('ViewerPage Load Error: $error');
                return const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.broken_image, color: Colors.white, size: 48),
                    SizedBox(height: 8),
                    Text('无法加载图片 (403/404)', style: TextStyle(color: Colors.white)),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
