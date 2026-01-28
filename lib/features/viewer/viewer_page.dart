import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import '../../core/models/uni_wallpaper.dart';
import '../../core/log/logger_store.dart';

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

  late final LoggerStore _log;

  // 候选 URL（会按顺序尝试）
  late final List<_Candidate> _candidates;

  int _idx = 0;
  bool _showingThumb = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _log = context.read<LoggerStore>();

    _candidates = _buildCandidates(widget.wallpaper);

    // 打开即打日志（你现在就是靠这个排错）
    _log.d(
      _tag,
      'Open',
      details: [
        'id=${widget.wallpaper.id}',
        'size=${widget.wallpaper.width}x${widget.wallpaper.height}',
        'thumbUrl=${widget.wallpaper.thumbUrl}',
        'fullUrl=${widget.wallpaper.fullUrl}',
        'candidates=${_candidates.map((e) => e.name).toList()}',
      ].join('\n'),
    );
  }

  // ✅ 动态 Headers：尽量“按目标域自动算 Referer”，同时 UA 统一手机 UA
  Map<String, String> _headersForUrl(String url) {
    if (url.isEmpty) return const {};
    try {
      final uri = Uri.parse(url);
      final origin = '${uri.scheme}://${uri.host}/';

      // 特殊修正：Wallspic 防盗链常要求 referer 指向主站（而不是 img3 子域）
      // 你已验证列表页 referer 用 https://wallspic.com/ 是 OK 的
      String referer = origin;
      if (uri.host.contains('wallspic.com')) {
        referer = 'https://wallspic.com/';
      }

      return {
        'Referer': referer,
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36',
        'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      };
    } catch (_) {
      return const {};
    }
  }

  // ✅ 针对 Wallspic：从缩略图推导“更可能存在的非 500x 版本”
  // 注意：你日志里 404 的 fullUrl 本质是 “thumb 去掉 -500x 后” => 该资源不存在
  // 所以这里只当一个候选，不强依赖它一定存在。
  String _tryUpgradeFromThumb(String thumbUrl) {
    if (thumbUrl.isEmpty) return thumbUrl;

    // 常见：...-500x.jpg => ... .jpg
    final upgraded = thumbUrl.replaceAll(RegExp(r'-500x(\.[a-zA-Z0-9]+)$'), r'$1');
    return upgraded;
  }

  // ✅ 如果你 JS 端用了 weserv 代理：这里也能从直链生成一个“代理候选”
  // 但注意：是否允许代理、代理是否稳定，不在这里争论；这里只做候选兜底。
  String _toWeserv(String url) {
    if (url.isEmpty) return url;
    final raw = url.replaceFirst(RegExp(r'^https?://'), '');
    return 'https://images.weserv.nl/?url=${Uri.encodeComponent(raw)}&n=-1';
  }

  List<_Candidate> _buildCandidates(UniWallpaper w) {
    final thumb = (w.thumbUrl.isNotEmpty) ? w.thumbUrl : w.fullUrl;
    final full = w.fullUrl;

    // 去重保持顺序
    final seen = <String>{};
    void add(List<_Candidate> out, String name, String url) {
      final u = url.trim();
      if (u.isEmpty) return;
      if (seen.contains(u)) return;
      seen.add(u);
      out.add(_Candidate(name: name, url: u));
    }

    final out = <_Candidate>[];

    // 1) 先尝试 fullUrl（来源给的“原始”）
    add(out, 'full', full);

    // 2) 如果 fullUrl 本身就是 thumb（或疑似预览），尝试从 thumb 升级
    final upgraded = _tryUpgradeFromThumb(thumb);
    add(out, 'thumb_upgraded', upgraded);

    // 3) thumb 本身（至少能看）
    add(out, 'thumb', thumb);

    // 4) 代理兜底（对任何源都通用：把候选再各自加一份 weserv）
    // 只要你环境允许走这个域名，它就是最后一层兜底。
    add(out, 'full_weserv', _toWeserv(full));
    add(out, 'upgraded_weserv', _toWeserv(upgraded));
    add(out, 'thumb_weserv', _toWeserv(thumb));

    return out;
  }

  void _onImageError(Object error) {
    final cur = _candidates[_idx];
    final headers = _headersForUrl(cur.url);

    // 记录错误（你需要的就是这个）
    _log.e(
      _tag,
      'Load error',
      details: [
        'candidate=${cur.name}',
        'idx=$_idx/${_candidates.length - 1}',
        'url=${cur.url}',
        'error=$error',
        'headers=$headers',
      ].join('\n'),
    );

    // 自动回退到下一个候选
    if (_idx < _candidates.length - 1) {
      setState(() {
        _idx += 1;
        // 当走到 thumb/相关候选时，标记一下 UI 状态（可选）
        _showingThumb = _candidates[_idx].name.contains('thumb');
      });

      final next = _candidates[_idx];
      _log.w(
        _tag,
        'Fallback',
        details: 'switch_to=${next.name}\nurl=${next.url}',
      );
    } else {
      // 已经无路可退
      _log.e(
        _tag,
        'Exhausted',
        details: 'no_more_candidates',
      );
      setState(() {
        _showingThumb = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.wallpaper;
    final heroTag = w.id.isNotEmpty ? w.id : w.fullUrl;

    final cur = _candidates[_idx];
    final curHeaders = _headersForUrl(cur.url);

    final titleText = '${w.width} × ${w.height}'
        '${_showingThumb ? '（预览）' : ''}'
        '  ${cur.name}';

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.35),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(
          titleText,
          style: const TextStyle(fontSize: 12),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: '重试/下一个候选',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _log.i(_tag, 'Manual retry', details: 'idx=$_idx name=${cur.name}');
              setState(() {
                // 手动点：优先换到下一个；如果已经最后一个就回到第一个
                _idx = (_idx + 1) % _candidates.length;
                _showingThumb = _candidates[_idx].name.contains('thumb');
              });
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
              httpHeaders: curHeaders,
              fit: BoxFit.contain,
              fadeInDuration: const Duration(milliseconds: 120),
              fadeOutDuration: const Duration(milliseconds: 120),
              // 兜底：显示一个加载指示
              placeholder: (_, __) => const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
              errorWidget: (_, __, error) {
                // 这里不要直接 return 错误 UI ——先触发回退
                // 但 CachedNetworkImage 的 errorWidget 不能异步 setState 里再 build 返回，
                // 所以用 microtask 触发回退，再暂时显示一个轻量占位。
                scheduleMicrotask(() => _onImageError(error));

                return const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.broken_image, color: Colors.white, size: 48),
                    SizedBox(height: 8),
                    Text(
                      '加载失败，正在尝试备用链接…',
                      style: TextStyle(color: Colors.white70),
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

class _Candidate {
  final String name;
  final String url;
  const _Candidate({required this.name, required this.url});
}