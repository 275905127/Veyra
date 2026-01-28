import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import '../../core/models/uni_wallpaper.dart';
import '../../core/services/wallpaper_service.dart';

class ViewerPage extends StatelessWidget {
  final UniWallpaper wallpaper;

  const ViewerPage({
    super.key,
    required this.wallpaper,
  });

  @override
  Widget build(BuildContext context) {
    final headers = context.read<WallpaperService>().commonImageHeaders;
    // 优先使用 ID 作为 Hero Tag，与列表页保持一致
    final heroTag = wallpaper.id.isNotEmpty ? wallpaper.id : wallpaper.fullUrl;
    
    final thumbUrl = wallpaper.thumbUrl.isNotEmpty ? wallpaper.thumbUrl : wallpaper.fullUrl;

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
              imageUrl: wallpaper.fullUrl,
              httpHeaders: headers,
              fit: BoxFit.contain,
              // 使用缩略图作为占位，平滑过渡
              placeholder: (c, url) => CachedNetworkImage(
                imageUrl: thumbUrl,
                httpHeaders: headers,
                fit: BoxFit.contain,
                // 缩略图本身还在加载时的占位（通常很快）
                placeholder: (_, __) => const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
              errorWidget: (c, _, __) => const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.broken_image, color: Colors.white, size: 48),
                  SizedBox(height: 8),
                  Text('无法加载图片', style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}