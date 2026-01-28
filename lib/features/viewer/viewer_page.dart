import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import '../../core/models/uni_wallpaper.dart';
import '../../core/log/logger_store.dart';

class ViewerPage extends StatelessWidget {
  final UniWallpaper wallpaper;

  const ViewerPage({
    super.key,
    required this.wallpaper,
  });

  Map<String, String> _getDynamicHeaders(String url) {
    if (url.isEmpty) return const {};
    try {
      final uri = Uri.parse(url);

      // 默认：用目标 host 的 origin
      String referer = '${uri.scheme}://${uri.host}/';

      // ✅ Wallspic/Akspic：强制主站 referer（不要用 img1/img2/img3 的 referer）
      if (url.contains('wallspic.com') || url.contains('akspic.ru')) {
        referer = 'https://wallspic.com/';
      }

      // ✅ Pixiv(pximg)：必须配 pixiv.net Referer
      if (url.contains('pximg') || url.contains('pixiv')) {
        referer = 'https://www.pixiv.net/';
      }

      return {
        'Referer': referer,
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
    // ✅ 自动从 Provider 取 LoggerStore（不再依赖外面传参）
    final logger = context.read<LoggerStore>();

    final heroTag = wallpaper.id.isNotEmpty ? wallpaper.id : wallpaper.fullUrl;
    final thumbUrl =
        wallpaper.thumbUrl.isNotEmpty ? wallpaper.thumbUrl : wallpaper.fullUrl;
    final fullUrl = wallpaper.fullUrl;

    final fullHeaders = _getDynamicHeaders(fullUrl);
    final thumbHeaders = _getDynamicHeaders(thumbUrl);

    logger.d(
      'ViewerPage',
      'Open',
      details: [
        'id=${wallpaper.id}',
        'size=${wallpaper.width}x${wallpaper.height}',
        'thumbUrl=$thumbUrl',
        'thumbHeaders=$thumbHeaders',
        'fullUrl=$fullUrl',
        'fullHeaders=$fullHeaders',
      ].join('\n'),
    );

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.3),
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

              // ✅ 大图加载过程中：先用缩略图占位
              placeholder: (_, __) => CachedNetworkImage(
                imageUrl: thumbUrl,
                httpHeaders: thumbHeaders,
                fit: BoxFit.contain,
                placeholder: (_, __) => const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
                errorWidget: (_, url, error) {
                  logger.e(
                    'ViewerPage',
                    'Thumb error',
                    details: 'url=$url\nerror=$error\nheaders=$thumbHeaders',
                  );
                  return const SizedBox.shrink();
                },
              ),

              // ✅ 大图加载失败
              errorWidget: (_, url, error) {
                logger.e(
                  'ViewerPage',
                  'Full error',
                  details: 'url=$url\nerror=$error\nheaders=$fullHeaders',
                );

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

              // ✅ 大图加载成功：打日志（注意：CachedNetworkImage 没有 onSuccess 回调，
              // 这里用 imageBuilder 作为“成功”的信号）
              imageBuilder: (_, imageProvider) {
                logger.i(
                  'ViewerPage',
                  'Full loaded',
                  details: 'fullUrl=$fullUrl',
                );
                return Image(
                  image: imageProvider,
                  fit: BoxFit.contain,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}