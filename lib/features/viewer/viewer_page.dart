import 'dart:math';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import '../../core/log/logger_store.dart';
import '../../core/models/uni_wallpaper.dart';

class ViewerPage extends StatefulWidget {
  final UniWallpaper wallpaper;

  const ViewerPage({
    super.key,
    required this.wallpaper,
  });

  @override
  State<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<ViewerPage> {
  static const _tag = 'ViewerPage';

  double _dragOffset = 0;

  @override
  void initState() {
    super.initState();

    _log(
      'Open',
      details:
          'id=${widget.wallpaper.id}\nurl=${widget.wallpaper.fullUrl}',
    );
  }

  // -------------------------
  // 手势关闭
  // -------------------------

  void _onVerticalDragUpdate(DragUpdateDetails d) {
    setState(() {
      _dragOffset += d.delta.dy;
      if (_dragOffset < 0) _dragOffset = 0;
    });
  }

  void _onVerticalDragEnd(DragEndDetails d) {
    if (_dragOffset > 120) {
      Navigator.pop(context);
    } else {
      setState(() => _dragOffset = 0);
    }
  }

  // -------------------------
  // Headers
  // -------------------------

  Map<String, String> _headersForUrl(String url) {
    if (widget.wallpaper.headers != null &&
        widget.wallpaper.headers!.isNotEmpty) {
      return widget.wallpaper.headers!;
    }

    try {
      final uri = Uri.parse(url);
      final origin = '${uri.scheme}://${uri.host}/';

      return {
        'Referer': origin,
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122 Mobile Safari/537.36',
      };
    } catch (_) {
      return const {};
    }
  }

  // -------------------------
  // 日志
  // -------------------------

  void _log(String msg, {String? details}) {
    try {
      context.read<LoggerStore>().d(_tag, msg, details: details);
    } catch (_) {}
  }

  void _logErr(String msg, {String? details}) {
    try {
      context.read<LoggerStore>().e(_tag, msg, details: details);
    } catch (_) {}
  }

  // -------------------------
  // UI
  // -------------------------

  @override
  Widget build(BuildContext context) {
    final w = widget.wallpaper;

    final heroTag = w.id.isNotEmpty ? w.id : w.fullUrl;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onVerticalDragUpdate: _onVerticalDragUpdate,
        onVerticalDragEnd: _onVerticalDragEnd,
        child: Stack(
          children: [
            // 图片
            Positioned.fill(
              top: _dragOffset,
              child: Center(
                child: Hero(
                  tag: heroTag,
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: CachedNetworkImage(
                      imageUrl: w.fullUrl,
                      httpHeaders: _headersForUrl(w.fullUrl),
                      fit: BoxFit.contain,
                      placeholder: (_, __) => const Center(
                        child: CircularProgressIndicator(
                          color: Colors.white,
                        ),
                      ),
                      errorWidget: (_, __, error) {
                        _logErr(
                          'Load error',
                          details:
                              'url=${w.fullUrl}\nerror=$error',
                        );
                        return const Icon(
                          Icons.broken_image,
                          color: Colors.white54,
                          size: 64,
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),

            // 顶部栏
            SafeArea(
              child: AppBar(
                backgroundColor: Colors.black.withOpacity(0.3),
                elevation: 0,
                leading: const BackButton(color: Colors.white),
                title: Text(
                  '${w.width} × ${w.height}',
                  style: const TextStyle(fontSize: 13),
                ),
                centerTitle: true,
              ),
            ),

            // 底部信息
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _InfoPanel(wallpaper: w),
            ),
          ],
        ),
      ),
    );
  }
}

/* -----------------------------
   信息面板
--------------------------------*/

class _InfoPanel extends StatelessWidget {
  final UniWallpaper wallpaper;

  const _InfoPanel({required this.wallpaper});

  @override
  Widget build(BuildContext context) {
    final w = wallpaper;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withOpacity(0.85),
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (w.uploader != null)
            Text(
              'by ${w.uploader}',
              style: const TextStyle(
                color: Colors.white70,
              ),
            ),

          const SizedBox(height: 6),

          Wrap(
            spacing: 12,
            children: [
              _Meta('${w.width} × ${w.height}'),
              if (w.tags.isNotEmpty) _Meta(w.tags.take(3).join(', ')),
            ],
          ),

          const SizedBox(height: 12),

          const _ActionRow(),
        ],
      ),
    );
  }
}

/* -----------------------------
   操作栏
--------------------------------*/

class _ActionRow extends StatelessWidget {
  const _ActionRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: const [
        _Action(icon: Icons.download, label: '下载'),
        _Action(icon: Icons.wallpaper, label: '设为壁纸'),
        _Action(icon: Icons.favorite_border, label: '收藏'),
        _Action(icon: Icons.share, label: '分享'),
      ],
    );
  }
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String label;

  const _Action({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

/* -----------------------------
   小组件
--------------------------------*/

class _Meta extends StatelessWidget {
  final String text;

  const _Meta(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white70,
        fontSize: 12,
      ),
    );
  }
}