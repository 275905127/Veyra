import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/models/uni_wallpaper.dart';
import '../../core/log/logger_store.dart'; // ⬅️ 你把 LoggerStore 放在哪就改成对应路径

class ViewerPage extends StatelessWidget {
  final UniWallpaper wallpaper;

  /// ✅ 注入内置日志（不注入也能跑，只是不写面板日志）
  final LoggerStore? logger;

  const ViewerPage({
    super.key,
    required this.wallpaper,
    this.logger,
  });

  void _logD(String msg, {String? details}) {
    // tag 统一用 ViewerPage，方便你在日志面板里搜索
    logger?.d('ViewerPage', msg, details: details);
  }

  /// ✅ 动态 Header：防盗链真正有效的 Referer
  /// - Wallspic/Akspic：Referer 必须是 https://wallspic.com/（不是 img*.wallspic.com）
  /// - Pixiv：pximg 必须配 https://www.pixiv.net/
  Map<String, String> _getDynamicHeaders(String url) {
    if (url.isEmpty) return const {};
    try {
      final uri = Uri.parse(url);

      // 默认：用目标 host 的 origin
      String referer = '${uri.scheme}://${uri.host}/';

      // ✅ Wallspic / Akspic：用主站 Referer
      if (url.contains('wallspic.com') || url.contains('akspic.ru')) {
        referer = 'https://wallspic.com/';
      }

      // ✅ Pixiv：pximg 必须配 pixiv.net Referer
      if (url.contains('pximg') || url.contains('pixiv')) {
        referer = 'https://www.pixiv.net/';
      }

      return {
        'Referer': referer,
        // ✅ 用手机 UA 更稳
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36',
        'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      };
    } catch (_) {
      return const {};
    }
  }

  @override
  Widget build(BuildContext context) {
    final heroTag = wallpaper.id.isNotEmpty ? wallpaper.id : wallpaper.fullUrl;

    final thumbUrl =
        wallpaper.thumbUrl.isNotEmpty ? wallpaper.thumbUrl : wallpaper.fullUrl;

    final fullUrl = wallpaper.fullUrl;

    final fullHeaders = _getDynamicHeaders(fullUrl);
    final thumbHeaders = _getDynamicHeaders(thumbUrl);

    // ✅ 写入内置日志面板（你没有控制台也能看）
    _logD(
      'Open viewer',
      details: [
        'id=${wallpaper.id}',
        'size=${wallpaper.width}x${wallpaper.height}',
        'fullUrl=$fullUrl',
        'fullHeaders=$fullHeaders',
        'thumbUrl=$thumbUrl',
        'thumbHeaders=$thumbHeaders',
      ].join('\n'),
    );

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.3),
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
              httpHeaders: fullHeaders,
              fit: BoxFit.contain,
              placeholder: (c, url) => CachedNetworkImage(
                imageUrl: thumbUrl,
                httpHeaders: thumbHeaders,
                fit: BoxFit.contain,
                placeholder: (_, __) => const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
                errorWidget: (_, __, ___) {
                  _logD(
                    'Thumb load error',
                    details: 'thumbUrl=$thumbUrl\nthumbHeaders=$thumbHeaders',
                  );
                  return const SizedBox.shrink();
                },
              ),
              errorWidget: (c, url, error) {
                _logD(
                  'Full load error',
                  details: [
                    'url=$url',
                    'error=$error',
                    'fullUrl=$fullUrl',
                    'fullHeaders=$fullHeaders',
                  ].join('\n'),
                );
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