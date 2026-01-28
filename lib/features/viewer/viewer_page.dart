import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/models/uni_wallpaper.dart';

class ViewerPage extends StatelessWidget {
  final UniWallpaper wallpaper;

  const ViewerPage({
    super.key,
    required this.wallpaper,
  });

  /// ✅ 动态 Header：针对防盗链做“真实可用”的 Referer 修正
  /// - Wallspic/akspic：通常要求 Referer=主站域名，而不是 img*.wallspic.com
  /// - Pixiv：pximg 必须配 Referer=https://www.pixiv.net/
  Map<String, String> _getDynamicHeaders(String url) {
    if (url.isEmpty) return const {};
    try {
      final uri = Uri.parse(url);

      // 默认：用目标 host 的 origin
      String referer = '${uri.scheme}://${uri.host}/';

      // ✅ Wallspic / Akspic 特判：用主站 Referer
      if (url.contains('wallspic.com') || url.contains('akspic.ru')) {
        // 建议用主站根域；也可以换成 https://wallspic.com/cn
        referer = 'https://wallspic.com/';
      }

      // ✅ Pixiv 特判：pximg 必须配 pixiv.net Referer
      if (url.contains('pximg') || url.contains('pixiv')) {
        referer = 'https://www.pixiv.net/';
      }

      return {
        'Referer': referer,

        // ✅ 建议使用手机 UA（有些图源会按 UA 策略拦 Windows UA）
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36',

        // 可选：有些站更挑 header，补齐 Accept/Language 更稳
        'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      };
    } catch (_) {
      return const {};
    }
  }

  @override
  Widget build(BuildContext context) {
    // 优先用 ID 作为 Hero tag
    final heroTag = wallpaper.id.isNotEmpty ? wallpaper.id : wallpaper.fullUrl;

    // thumbUrl 为空就回退 fullUrl（避免空）
    final thumbUrl =
        wallpaper.thumbUrl.isNotEmpty ? wallpaper.thumbUrl : wallpaper.fullUrl;

    final fullUrl = wallpaper.fullUrl;

    // ✅ 为大图/缩略图生成 header
    final fullHeaders = _getDynamicHeaders(fullUrl);
    final thumbHeaders = _getDynamicHeaders(thumbUrl);

    // ✅ 日志：你点开大图后看控制台，就能确认 Referer 是否正确
    debugPrint('ViewerPage FULL_URL=$fullUrl');
    debugPrint('ViewerPage FULL_HDR=$fullHeaders');
    debugPrint('ViewerPage THMB_URL=$thumbUrl');
    debugPrint('ViewerPage THMB_HDR=$thumbHeaders');

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
                errorWidget: (_, __, ___) => const SizedBox.shrink(),
              ),
              errorWidget: (c, url, error) {
                debugPrint('ViewerPage Load Error url=$url error=$error');
                return const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.broken_image, color: Colors.white, size: 48),
                    SizedBox(height: 8),
                    Text(
                      '无法加载图片 (403/404)',
                      style: TextStyle(color: Colors.white),
                    ),
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