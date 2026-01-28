import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'shimmer_placeholder.dart';

class VeyraImageCard extends StatefulWidget {
  final String imageUrl;
  final String heroTag;
  final VoidCallback? onTap;
  final double? aspectRatio;
  final BoxFit fit;
  final int? memCacheWidth;
  // ✅ 新增：接收请求头
  final Map<String, String>? headers;

  const VeyraImageCard({
    super.key,
    required this.imageUrl,
    required this.heroTag,
    this.onTap,
    this.aspectRatio,
    this.fit = BoxFit.cover,
    this.memCacheWidth,
    this.headers, // ✅ 构造函数加入
  });

  @override
  State<VeyraImageCard> createState() => _VeyraImageCardState();
}

class _VeyraImageCardState extends State<VeyraImageCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    if (widget.onTap != null) _controller.forward();
  }

  void _onTapUp(TapUpDetails details) {
    if (widget.onTap != null) _controller.reverse();
  }

  void _onTapCancel() {
    if (widget.onTap != null) _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    Widget image = CachedNetworkImage(
      imageUrl: widget.imageUrl,
      fit: widget.fit,
      memCacheWidth: widget.memCacheWidth,
      httpHeaders: widget.headers, // ✅ 传给 CachedNetworkImage
      placeholder: (context, url) => const ShimmerPlaceholder(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
      // ✅✅✅ 修改这里：把错误打印出来！
      errorWidget: (context, url, error) {
        // 🔴 这一步非常重要，它会告诉我们真相
        print("--------------------------------------------------");
        print("❌ 图片挂了: $url");
        print("❌ 错误原因: $error");
        if (error.toString().contains("403")) {
           print("💡 提示: 403 表示 Referer 被服务器拒绝了");
        }
        if (error.toString().contains("Handshake")) {
           print("💡 提示: 证书/SSL错误，可能是VPN或网络问题");
        }
        print("--------------------------------------------------");

        return Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Icon(Icons.broken_image_rounded, color: Colors.grey),
        );
      },
    );

    Widget content = ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: widget.aspectRatio != null
          ? AspectRatio(aspectRatio: widget.aspectRatio!, child: image)
          : image,
    );

    content = Hero(
      tag: widget.heroTag,
      child: content,
      flightShuttleBuilder: (
        flightContext,
        animation,
        flightDirection,
        fromHeroContext,
        toHeroContext,
      ) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: fromHeroContext.widget,
        );
      },
    );

    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) => Transform.scale(
        scale: _scaleAnimation.value,
        child: child,
      ),
      child: GestureDetector(
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: _onTapCancel,
        onTap: widget.onTap,
        child: content,
      ),
    );
  }
}
