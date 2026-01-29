// lib/features/viewer/viewer_page.dart
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import '../../core/log/logger_store.dart';
import '../../core/models/uni_wallpaper.dart';

enum _CandidateType {
  full,
  fullWeserv,
  thumbUpgraded,
  thumb,
}

class _Candidate {
  final _CandidateType type;
  final String url;
  final Map<String, String> headers;

  const _Candidate(this.type, this.url, this.headers);

  String get name {
    switch (type) {
      case _CandidateType.full:
        return 'full';
      case _CandidateType.fullWeserv:
        return 'full_weserv';
      case _CandidateType.thumbUpgraded:
        return 'thumb_upgraded';
      case _CandidateType.thumb:
        return 'thumb';
    }
  }
}

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

  int _idx = 0;
  late final List<_Candidate> _candidates;

  @override
  void initState() {
    super.initState();
    _candidates = _buildCandidates(widget.wallpaper);

    _log('Open', details: [
      'id=${widget.wallpaper.id}',
      'size=${widget.wallpaper.width}x${widget.wallpaper.height}',
      for (final c in _candidates) '${c.name}=${c.url}',
    ].join('\n'));
  }

  // ======= 核心修复：识别 weserv，避免二次套娃 =======
  bool _isWeserv(String url) {
    try {
      final u = Uri.parse(url);
      final h = (u.host).toLowerCase();
      return h.contains('images.weserv.nl') || h.contains('wsrv.nl');
    } catch (_) {
      return false;
    }
  }

  String _toWeserv(String url) {
    if (url.isEmpty) return url;

    // ✅ 已经是 weserv 的链接，直接返回（避免你日志里的 double-weserv 404）
    if (_isWeserv(url)) return url;

    // weserv：把协议去掉更稳
    final raw = url.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');
    return 'https://images.weserv.nl/?url=${Uri.encodeComponent(raw)}&n=-1';
  }

  // ======= headers：按站点修正 Referer =======
  Map<String, String> _headersForUrl(String url) {
    if (url.isEmpty) return const {};
    try {
      final uri = Uri.parse(url);

      // weserv 本身一般不需要 referer；但你日志里打印了，也无所谓
      if (_isWeserv(url)) {
        return const {
          'Referer': 'https://images.weserv.nl/',
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36',
          'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        };
      }

      final host = uri.host.toLowerCase();
      final origin = '${uri.scheme}://${uri.host}/';

      // ✅ Wallspic：要求 referer 指向主站
      if (host.contains('wallspic.com')) {
        return const {
          'Referer': 'https://wallspic.com/',
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36',
          'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        };
      }

      // ✅ Wallhere：c.wallhere.com / w.wallhere.com 也通常要 referer=wallhere.com
      if (host == 'c.wallhere.com' ||
          host == 'w.wallhere.com' ||
          host.endsWith('.wallhere.com') ||
          host == 'wallhere.com') {
        return const {
          'Referer': 'https://wallhere.com/',
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36',
          'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        };
      }

      // 默认：按图片域名 origin 作为 referer
      return {
        'Referer': origin,
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36',
        'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      };
    } catch (_) {
      return const {};
    }
  }

  // ✅ 从缩略图推导“更可能存在的非 500x 版本”
  String _upgradeThumb(String url) {
    if (url.isEmpty) return url;

    // 如果是 weserv，就不要在这里改 path 了（改了也没意义，还容易出奇怪 404）
    if (_isWeserv(url)) return url;

    // 常见：...-500x.jpg -> ....jpg
    return url.replaceAllMapped(
      RegExp(r'-\d{2,4}x(?=\.[a-zA-Z]{3,4}$)'),
      (_) => '',
    );
  }

  List<_Candidate> _buildCandidates(UniWallpaper w) {
    final full = (w.fullUrl.isNotEmpty) ? w.fullUrl : '';
    final thumb = (w.thumbUrl.isNotEmpty) ? w.thumbUrl : full;

    final out = <_Candidate>[];

    if (full.isNotEmpty) {
      out.add(_Candidate(_CandidateType.full, full, _headersForUrl(full)));
    }

    // full_weserv：只有当 full 不是 weserv 时才添加（否则重复）
    if (full.isNotEmpty && !_isWeserv(full)) {
      final u = _toWeserv(full);
      out.add(_Candidate(_CandidateType.fullWeserv, u, _headersForUrl(u)));
    }

    // thumb_upgraded
    if (thumb.isNotEmpty) {
      final up = _upgradeThumb(thumb);
      if (up.isNotEmpty && up != thumb) {
        out.add(_Candidate(_CandidateType.thumbUpgraded, up, _headersForUrl(up)));
      }
    }

    // thumb
    if (thumb.isNotEmpty) {
      out.add(_Candidate(_CandidateType.thumb, thumb, _headersForUrl(thumb)));
    }

    // 去重（同 URL 留第一个）
    final seen = <String>{};
    return out.where((c) => seen.add(c.url)).toList(growable: false);
  }

  void _log(String msg, {String? details}) {
    try {
      context.read<LoggerStore>().d(_tag, msg, details: details);
    } catch (_) {
      // ignore
    }
  }

  void _logWarn(String msg, {String? details}) {
    try {
      context.read<LoggerStore>().w(_tag, msg, details: details);
    } catch (_) {
      // ignore
    }
  }

  void _logErr(String msg, {String? details}) {
    try {
      context.read<LoggerStore>().e(_tag, msg, details: details);
    } catch (_) {
      // ignore
    }
  }

  void _nextCandidate(String reason) {
    if (_idx >= _candidates.length - 1) {
      _logErr('Exhausted', details: 'no_more_candidates');
      return;
    }
    final to = _candidates[_idx + 1];

    _logWarn(
      'Fallback',
      details: 'reason=$reason\nswitch_to=${to.name}\nurl=${to.url}',
    );

    setState(() => _idx = min(_idx + 1, _candidates.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.wallpaper;
    final heroTag = w.id.isNotEmpty ? w.id : w.fullUrl;

    final cur = _candidates.isNotEmpty ? _candidates[_idx] : const _Candidate(_CandidateType.full, '', {});
    final titleSize = '${w.width} × ${w.height}';

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.3),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(
          '$titleSize   ${cur.name}',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          IconButton(
            tooltip: '重试',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _log('Retry', details: 'candidate=${cur.name}\nurl=${cur.url}');
              setState(() {});
            },
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
              imageUrl: cur.url,
              httpHeaders: cur.headers,
              fit: BoxFit.contain,
              placeholder: (_, __) => const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
              errorWidget: (_, __, error) {
                _logErr(
                  'Load error',
                  details: [
                    'candidate=${cur.name}',
                    'idx=${_idx + 1}/${_candidates.length}',
                    'url=${cur.url}',
                    'error=$error',
                    'headers=${cur.headers}',
                  ].join('\n'),
                );

                _nextCandidate(cur.name);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
  }
}