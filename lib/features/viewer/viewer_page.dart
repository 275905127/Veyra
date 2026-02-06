import 'package:flutter/material.dart';
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
  double _dragOffset = 0;

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

  @override
  Widget build(BuildContext context) {
    final w = widget.wallpaper;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onVerticalDragUpdate: _onVerticalDragUpdate,
        onVerticalDragEnd: _onVerticalDragEnd,
        child: Stack(
          children: [
            /// 图片层
            Positioned.fill(
              top: _dragOffset,
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: Image.network(
                    w.imageUrl,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),

            /// 顶部返回
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),

            /// 底部信息区
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
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (wallpaper.title != null)
            Text(
              wallpaper.title!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),

          if (wallpaper.author != null)
            Text(
              "by ${wallpaper.author}",
              style: const TextStyle(color: Colors.white70),
            ),

          const SizedBox(height: 6),

          Wrap(
            spacing: 12,
            children: [
              if (wallpaper.sourceName != null)
                _Meta(wallpaper.sourceName!),

              if (wallpaper.width != null &&
                  wallpaper.height != null)
                _Meta("${wallpaper.width} × ${wallpaper.height}"),

              if (wallpaper.size != null)
                _Meta(_formatSize(wallpaper.size!)),
            ],
          ),

          const SizedBox(height: 12),

          _ActionRow(wallpaper: wallpaper),
        ],
      ),
    );
  }
}

/* -----------------------------
   操作栏
--------------------------------*/

class _ActionRow extends StatelessWidget {
  final UniWallpaper wallpaper;

  const _ActionRow({required this.wallpaper});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: const [
        _Action(icon: Icons.download, label: "下载"),
        _Action(icon: Icons.wallpaper, label: "设为壁纸"),
        _Action(icon: Icons.favorite_border, label: "收藏"),
        _Action(icon: Icons.share, label: "分享"),
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
          style: const TextStyle(color: Colors.white70, fontSize: 12),
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
      style: const TextStyle(color: Colors.white70, fontSize: 12),
    );
  }
}

String _formatSize(int bytes) {
  if (bytes < 1024) return "$bytes B";
  if (bytes < 1024 * 1024) {
    return "${(bytes / 1024).toStringAsFixed(1)} KB";
  }
  return "${(bytes / 1024 / 1024).toStringAsFixed(1)} MB";
}