import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';

import '../../core/models/source.dart';
import '../../core/models/uni_wallpaper.dart';
import '../../core/services/wallpaper_service.dart';
import '../../core/storage/api_key_store.dart';
import '../../core/storage/pack_store.dart';
import '../../core/storage/source_store.dart';
import '../../gen_l10n/app_localizations.dart';
import 'browse_controller.dart';
import 'widgets/filter_sheet.dart';
import '../../core/ui/widgets/image_card.dart';
import '../../core/ui/widgets/shimmer_placeholder.dart';
import '../viewer/viewer_page.dart';

class BrowsePage extends StatefulWidget {
  const BrowsePage({super.key});

  @override
  State<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends State<BrowsePage> {
  BrowseController? _controller;
  String? _boundActiveId;
  bool _bindingScheduled = false;

  late final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    _controller?.dispose();
    super.dispose();
  }

  void _onScroll() {
    final c = _controller;
    if (c == null) return;
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    if (pos.pixels >= pos.maxScrollExtent - 320) {
      c.loadMore();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller ??= BrowseController(
      wallpaperService: context.read<WallpaperService>(),
      sourceStore: context.read<SourceStore>(),
    );
  }

  void _syncActiveToController(SourceRef? active) {
    final c = _controller;
    if (c == null) return;
    final activeId = active?.id;
    if (activeId == _boundActiveId) return;
    _boundActiveId = activeId;

    if (_bindingScheduled) return;
    _bindingScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _bindingScheduled = false;
      if (!mounted || _controller == null) return;
      if (active == null) {
        _controller!.resetToEmpty();
        return;
      }
      await _controller!.setSource(active);
    });
  }

  Future<void> _openFilterSheet(SourceRef active) async {
    final c = _controller;
    if (c == null) return;
    final sourceStore = context.read<SourceStore>();
    final packStore = context.read<PackStore>();
    final apiKeyStore = context.read<ApiKeyStore>();

    Map<String, dynamic> specRaw = const <String, dynamic>{};
    try {
      specRaw = await sourceStore.getSpecRaw(active.id);
    } catch (_) {
      specRaw = const <String, dynamic>{};
    }

    if (!mounted) return;
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FilterSheet(
        sourceId: active.id,
        specRaw: specRaw,
        initialFilters: c.filters,
        packStore: packStore,
        apiKeyStore: apiKeyStore,
      ),
    );

    if (!mounted || result == null) return;
    await c.setQuery(filters: result, refreshNow: true);
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null) return const SizedBox.shrink();

    final active = context.watch<SourceStore>().active;
    _syncActiveToController(active);

    return ChangeNotifierProvider.value(
      value: c,
      child: Consumer<BrowseController>(
        builder: (_, c, __) => Stack(
          children: <Widget>[
            _BrowseBody(
              scrollController: _scrollCtrl,
              items: c.items,
              loading: c.loading,
              error: c.error,
              onRetry: c.refresh,
              onRefresh: c.refresh,
            ),
            if (active != null)
              Positioned(
                right: 16,
                bottom: 16,
                child: FloatingActionButton.extended(
                  heroTag: 'browse_filter_fab',
                  onPressed: () => _openFilterSheet(active),
                  icon: const Icon(Icons.tune),
                  label: const Text('筛选'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BrowseBody extends StatelessWidget {
  final ScrollController scrollController;
  final List<UniWallpaper> items;
  final bool loading;
  final String? error;
  final Future<void> Function() onRefresh;
  final VoidCallback onRetry;

  const _BrowseBody({
    required this.scrollController,
    required this.items,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.onRefresh,
  });

  /// ✅ 关键修改：根据 URL 动态生成 Headers
  /// 这使得 App 可以自动适配 Pixiv、Wallhaven 等不同防盗链策略
  Map<String, String> _getDynamicHeaders(String url) {
    if (url.isEmpty) return const {};
    try {
      final uri = Uri.parse(url);
      // 默认策略：Referer = 协议 + 域名 (例如 https://www.pixiv.net/)
      // 大多数图床只要这个就能通过防盗链
      final origin = '${uri.scheme}://${uri.host}/';

      // 🛠️ 针对 Wallspic 的特殊修复
      // 如果图片 URL 包含 "wallspic"，强制把 Referer 设为主站
      if (url.contains('wallspic')) {
        referer = 'https://wallspic.com/';
      }
      return {
        'Referer': origin,
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      };
    } catch (_) {
      return const {};
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);

    if (loading && items.isEmpty) {
      return MasonryGridView.count(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 24),
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        itemCount: 12,
        itemBuilder: (context, index) {
          final aspect = index.isEven ? 0.7 : 1.0;
          return AspectRatio(
            aspectRatio: aspect,
            child: const ShimmerPlaceholder(),
          );
        },
      );
    }

    if (error != null && items.isEmpty) {
      return Center(
        child: FilledButton(
          onPressed: onRetry,
          child: Text(s.errorRetry),
        ),
      );
    }

    const physics = AlwaysScrollableScrollPhysics();
    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          controller: scrollController,
          physics: physics,
          children: const <Widget>[
            SizedBox(height: 240),
            Center(child: Text('没有内容')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: MasonryGridView.count(
        controller: scrollController,
        physics: physics,
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 24),
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        itemCount: items.length + 1,
        itemBuilder: (context, index) {
          if (index == items.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: loading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const SizedBox(height: 1),
              ),
            );
          }

          final w = items[index];
          final url = (w.thumbUrl.isNotEmpty ? w.thumbUrl : w.fullUrl).trim();
          if (url.isEmpty) return const SizedBox.shrink();

          // ✅ 1. 计算动态 Headers
          final headers = _getDynamicHeaders(url);

          return VeyraImageCard(
            imageUrl: url,
            heroTag: w.id.isNotEmpty ? w.id : w.fullUrl,
            memCacheWidth: 400,
            headers: headers, // ✅ 2. 传入 Headers (确保你已按之前步骤更新了 ImageCard 支持此参数)
            aspectRatio: (w.width > 0 && w.height > 0)
                ? (w.width / w.height)
                : 1.0,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ViewerPage(wallpaper: w),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
