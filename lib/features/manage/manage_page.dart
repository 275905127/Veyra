import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/source.dart';
import '../../core/storage/source_store.dart';
import '../../gen_l10n/app_localizations.dart';
import '../pack/pack_controller.dart';
import '../source/source_controller.dart';

class ManagePage extends StatelessWidget {
  const ManagePage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final sc = context.watch<SourceController>();
    final sources = sc.sources;
    final activeId = context.select<SourceStore, String?>((st) => st.active?.id);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: <Widget>[
        // ✅ 界面简化：只有一个列表，不需要 "Sources" 这种分段标题了
        // 或者保留一个简单的总标题
        Row(
          children: [
             Text(s.manageSectionSources, style: Theme.of(context).textTheme.titleMedium),
             const Spacer(),
             // 把导入按钮放在这里，或者AppBar (这里演示AppBar的逻辑，下面会把AppBar Actions更新)
          ],
        ),
        const SizedBox(height: 12),
        
        sources.isEmpty
            ? _HintCard(
                title: s.emptyNoSourcesTitle,
                body: s.emptyNoSourcesBody,
                icon: Icons.public_off_outlined,
              )
            : _SourceCardList(
                items: sources,
                activeId: activeId,
              ),
      ],
    );
  }
}

/// ✅ 更新 Actions：只保留“导入”和“刷新”
class ManagePageActions extends StatelessWidget {
  const ManagePageActions({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // 导入按钮：本质还是调用 PackController 安装，但用户感知上是“添加图源”
        IconButton(
          tooltip: s.actionImport,
          onPressed: () async {
            try {
              await context.read<PackController>().install();
            } catch (_) {}
          },
          icon: const Icon(Icons.add),
        ),
        IconButton(
          tooltip: s.actionRefresh,
          onPressed: () async {
            await context.read<SourceController>().load();
          },
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
  }
}

class _HintCard extends StatelessWidget {
  final String title;
  final String body;
  final IconData icon;

  const _HintCard({
    required this.title,
    required this.body,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 6),
                  Text(body, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceCardList extends StatelessWidget {
  final List<SourceRef> items;
  final String? activeId;

  const _SourceCardList({
    required this.items,
    required this.activeId,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          for (int i = 0; i < items.length; i++) ...<Widget>[
            _SourceTile(
              source: items[i],
              selected: items[i].id == activeId,
            ),
            if (i != items.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  final SourceRef source;
  final bool selected;

  const _SourceTile({
    required this.source,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;

    return ListTile(
      selected: selected,
      selectedColor: cs.primary,
      selectedTileColor: cs.primary.withOpacity(0.08),
      leading: Icon(Icons.extension), // 统一用拼图图标
      title: Text(source.name),
      subtitle: Text(source.ref),
      // ✅ 关键：点击进入图源
      onTap: () async {
        await context.read<SourceStore>().setActive(source);
      },
      // ✅ 关键：删除按钮现在执行“级联删除”
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: s.managePackUninstall,
        onPressed: () async {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('删除图源'),
              content: Text('确定要删除 "${source.name}" 吗？\n这将同时卸载对应的引擎包文件。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('删除', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          );

          if (confirm == true && context.mounted) {
            try {
              // 调用新的级联删除方法
              await context.read<SourceController>().deleteSource(source.id);
              
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(s.snackUninstalled)),
                );
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('删除失败: $e')),
                );
              }
            }
          }
        },
      ),
    );
  }
}
