
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

    // ✅ 重要：controller 也要 dispose（避免监听器泄漏）
    _controller?.dispose();

    super.dispose();
  }

  void _onScroll() {
    final c = _controller;
    if (c == null) return;
    if (!_scrollCtrl.hasClients) return;

    final pos = _scrollCtrl.position;
    // 接近底部就加载更多
    if (pos.pixels >= pos.maxScrollExtent - 320) {
      c.loadMore();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // 只初始化一次 controller（不要在这里 watch）
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

  // ✅ 关键：提前取出 store
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
    showDragHandle: false, // FilterSheet 自己有了 handle UI 或者我们用系统自带的 handle
    // 这里我们用系统自带的吧？之前的 FilterSheet 自绘了 handle。
    // 如果用系统自带的，可以删掉 FilterSheet 里的 handle UI。
    // 既然 FilterSheet 是 DraggableScrollableSheet，我们可以不在这里开 showDragHandle=true。
    // 但是 DraggableScrollableSheet 在 showModalBottomSheet 里通常需要。
    // 无论如何，新 FilterSheet 内部画了个 handle。这里设为 true 会有两个 handle。
    // 设为 false 比较安全。
    // 注意：filter_sheet.dart 使用 DraggableScrollableSheet，
    // 它通常作为 showModalBottomSheet 的 child 且 isScrollControlled: true。
    backgroundColor: Colors.transparent, // 让 sheet 自己控制背景
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
} // End of _openFilterSheet

  @override
  Widget build(BuildContext context) {
    // ... (unchanged)
    final c = _controller;
    if (c == null) return const SizedBox.shrink();

    // active 变化时触发同步
    final active = context.watch<SourceStore>().active;
    _syncActiveToController(active);

    final headers = context.read<WallpaperService>().commonImageHeaders;

    return ChangeNotifierProvider.value(
      value: c,
      child: Consumer<BrowseController>(
        builder: (_, c, __) => Stack(
          children: <Widget>[
            _BrowseBody(
              scrollController: _scrollCtrl,
              commonHeaders: headers,
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
// 恢复 _BrowseBody
class _BrowseBody extends StatelessWidget {
  final ScrollController scrollController;
  final Map<String, String> commonHeaders;

  final List<UniWallpaper> items;
  final bool loading;
  final String? error;

  final Future<void> Function() onRefresh;
  final VoidCallback onRetry;

  const _BrowseBody({
    required this.scrollController,
    required this.commonHeaders,
    required this.items,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);

    // 1. 全屏骨架屏加载态
    if (loading && items.isEmpty) {
      return MasonryGridView.count(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        itemCount: 12,
        itemBuilder: (context, index) {
          // 模拟瀑布流高低错落
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

    // RefreshIndicator 要“永远可滚动”
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

    // 瀑布流
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: MasonryGridView.count(
        controller: scrollController,
        physics: physics,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
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

          return VeyraImageCard(
            imageUrl: url,
            heroTag: w.id.isNotEmpty ? w.id : w.fullUrl,
            memCacheWidth: 400,
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

