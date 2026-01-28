import 'dart:async';
import 'dart:convert';

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
  // 当前尝试的 URL 列表
  late final List<String> _candidates;
  int _idx = 0;

  // 用于强制刷新图片（避免 CachedNetworkImage 复用旧状态）
  Key _imgKey = UniqueKey();

  LoggerStore? _log;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _log ??= context.read<LoggerStore>();
  }

  Map<String, String> _getDynamicHeaders(String url) {
    if (url.isEmpty) return const {};
    try {
      final uri = Uri.parse(url);

      // 代理域（weserv）一般不需要 Referer，但给了也无妨
      // 真实图域（img*.wallspic.com）需要 Referer 才不容易被挡
      String referer = '${uri.scheme}://${uri.host}/';
      if (url.contains('wallspic')) referer = 'https://wallspic.com/';

      return <String, String>{
        'Referer': referer,
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36',
        // 有些 CDN 对 Accept 更敏感，补一个
        'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      };
    } catch (_) {
      return const {};
    }
  }

  /// 如果你用了 weserv 代理：
  /// https://images.weserv.nl/?url=img3.wallspic.com/previews/...
  /// 这里把原始 url 解出来，方便推导真实地址
  String _unwrapWeserv(String u) {
    try {
      final uri = Uri.parse(u);
      if (uri.host != 'images.weserv.nl') return u;
      final raw = uri.queryParameters['url'];
      if (raw == null || raw.isEmpty) return u;

      // weserv 的 url 通常不带协议
      if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
      return 'https://$raw';
    } catch (_) {
      return u;
    }
  }

  List<String> _buildCandidates(UniWallpaper w) {
    final out = <String>[];
    void add(String? u) {
      if (u == null) return;
      final s = u.trim();
      if (s.isEmpty) return;
      if (!out.contains(s)) out.add(s);
    }

    // 1) 先用 fullUrl（你传进来的）
    add(w.fullUrl);

    // 2) 再用 thumbUrl（至少能显示）
    add(w.thumbUrl);

    // 3) 对 raw（如果是 weserv 代理，先解出来）
    final rawFull = _unwrapWeserv(w.fullUrl);
    final rawThumb = _unwrapWeserv(w.thumbUrl);

    // 4) 基于 raw 做推导
    for (final base in <String>[rawFull, rawThumb]) {
      if (base.isEmpty) continue;

      // A: 去掉 -500x
      add(base.replaceAllMapped(
        RegExp(r'-500x(\.[a-z0-9]+)$', caseSensitive: false),
        (m) => m.group(1) ?? '',
      ));

      // B: previews -> wallpapers
      if (base.contains('/previews/')) {
        final no500 = base.replaceAllMapped(
          RegExp(r'-500x(\.[a-z0-9]+)$', caseSensitive: false),
          (m) => m.group(1) ?? '',
        );
        add(no500.replaceFirst('/previews/', '/wallpapers/'));
        add(no500.replaceFirst('/previews/', '/originals/'));
      }

      // C: imgX 域名可能轮换（img1/img2/img3），做个轻量替换
      // 只对 wallspic 的 img 域做，避免误伤
      if (base.contains('.wallspic.com/')) {
        add(base.replaceFirst('img1.wallspic.com', 'img2.wallspic.com'));
        add(base.replaceFirst('img1.wallspic.com', 'img3.wallspic.com'));
        add(base.replaceFirst('img2.wallspic.com', 'img1.wallspic.com'));
        add(base.replaceFirst('img2.wallspic.com', 'img3.wallspic.com'));
        add(base.replaceFirst('img3.wallspic.com', 'img1.wallspic.com'));
        add(base.replaceFirst('img3.wallspic.com', 'img2.wallspic.com'));
      }
    }

    // 5) 如果你仍然要走代理（weserv），把推导结果再包一层代理
    // 这样在你网络对 img*.wallspic.com reset 的情况下，依然有机会加载
    for (final u in List<String>.from(out)) {
      final raw = _unwrapWeserv(u);
      if (raw.contains('.wallspic.com/') && !u.contains('images.weserv.nl')) {
        final stripped = raw.replaceFirst(RegExp(r'^https?://'), '');
        final proxied =
            'https://images.weserv.nl/?url=${Uri.encodeComponent(stripped)}&n=-1';
        add(proxied);
      }
    }

    return out;
  }

  void _logOpen() {
    final w = widget.wallpaper;
    final msg = StringBuffer()
      ..writeln('Open')
      ..writeln('id=${w.id}')
      ..writeln('size=${w.width}x${w.height}')
      ..writeln('thumbUrl=${w.thumbUrl}')
      ..writeln('fullUrl=${w.fullUrl}')
      ..writeln('candidates=${_candidates.length}');
    _log?.d('ViewerPage', msg.toString());
  }

  void _logFail(Object error, String url, Map<String, String> headers) {
    _log?.e(
      'ViewerPage',
      'Load failed',
      details: 'url=$url\nerror=$error\nheaders=$headers',
    );
  }

  void _nextCandidate() {
    if (!mounted) return;
    if (_idx + 1 >= _candidates.length) return;

    setState(() {
      _idx += 1;
      _imgKey = UniqueKey();
    });

    _log?.w(
      'ViewerPage',
      'Retry next candidate',
      details: 'idx=$_idx\nurl=${_candidates[_idx]}',
    );
  }

  @override
  void initState() {
    super.initState();
    _candidates = _buildCandidates(widget.wallpaper);
    // initState 里拿不到 Provider，所以日志放到 didChangeDependencies 之后
    scheduleMicrotask(() {
      if (!mounted) return;
      _logOpen();
      _log?.d('ViewerPage', 'Try first', details: 'url=${_candidates[_idx]}');
    });
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.wallpaper;
    final heroTag = w.id.isNotEmpty ? w.id : (w.fullUrl.isNotEmpty ? w.fullUrl : w.thumbUrl);

    final url = _candidates.isEmpty ? '' : _candidates[_idx];
    final headers = _getDynamicHeaders(url);

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.3),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          '${w.width} × ${w.height}',
          style: const TextStyle(fontSize: 14),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '下一个候选链接',
            icon: const Icon(Icons.refresh),
            onPressed: _nextCandidate,
          ),
        ],
      ),
      body: Center(
        child: Hero(
          tag: heroTag,
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: CachedNetworkImage(
              key: _imgKey,
              imageUrl: url,
              httpHeaders: headers,
              fit: BoxFit.contain,
              placeholder: (_, __) => const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
              errorWidget: (_, __, error) {
                _logFail(error, url, headers);

                // 自动尝试下一个候选
                // 这里用 microtask 避免在 build 中 setState
                scheduleMicrotask(_nextCandidate);

                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.broken_image, color: Colors.white, size: 48),
                    const SizedBox(height: 8),
                    Text(
                      '无法加载图片（${_idx + 1}/${_candidates.length}）',
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Text(
                        url,
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
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