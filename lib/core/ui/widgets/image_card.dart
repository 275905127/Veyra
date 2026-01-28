import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'shimmer_placeholder.dart';

/// 一个集成了 Hero、Shimmer 加载和按压反馈的高级图片卡片
class VeyraImageCard extends StatefulWidget {
  final String imageUrl;
  final String heroTag;
  final VoidCallback? onTap;
  final double? aspectRatio;
  final BoxFit fit;
  final int? memCacheWidth; // 内存优化

  const VeyraImageCard({
    super.key,
    required this.imageUrl,
    required this.heroTag,
    this.onTap,
    this.aspectRatio,
    this.fit = BoxFit.cover,
    this.memCacheWidth,
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
      memCacheWidth: widget.memCacheWidth, // 内存优化
      placeholder: (context, url) => const ShimmerPlaceholder(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
      errorWidget: (context, url, error) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Icon(Icons.broken_image_rounded, color: Colors.grey),
      ),
    );

    // 只有在 Hero 动画飞行时，不需要 ClipRRect（为了性能），但在静止时需要圆角
    // 这里我们直接切圆角
    Widget content = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: widget.aspectRatio != null
          ? AspectRatio(aspectRatio: widget.aspectRatio!, child: image)
          : image,
    );

    // Hero 包裹
    content = Hero(
      tag: widget.heroTag,
      child: content,
      // 避免 Hero 飞行时带有非 Material 的样式（如文字下划线等），虽然这里只是图片
      flightShuttleBuilder: (
        flightContext,
        animation,
        flightDirection,
        fromHeroContext,
        toHeroContext,
      ) {
        // 飞行时保持圆角
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: fromHeroContext.widget,
        );
      },
    );

    // 按压反馈包裹
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
