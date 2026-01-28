import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/engine_pack.dart';
import '../../core/models/source.dart';
import '../../core/storage/source_store.dart';
import '../../gen_l10n/app_localizations.dart';
import '../pack/pack_controller.dart';
import '../source/source_controller.dart';

/// 管理页（仅内容区）
///
/// 注意：不要在这里再包 Scaffold/AppBar，外层 HomeShell 统一负责。
class ManagePage extends StatelessWidget {
  const ManagePage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);

    final sc = context.watch<SourceController>();
    final sources = sc.sources;

    final pc = context.watch<PackController>();
    final packs = pc.packs;

    final activeId = context.select<SourceStore, String?>((st) => st.active?.id);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: <Widget>[
        _SectionHeader(title: s.manageSectionSources),
        const SizedBox(height: 8),
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
        const SizedBox(height: 20),
        _SectionHeader(title: s.manageSectionPacks),
        const SizedBox(height: 8),
        packs.isEmpty
            ? _HintCard(
                title: s.emptyNoPacksTitle,
                body: s.emptyNoPacksBody,
                icon: Icons.extension_off_outlined,
              )
            : _PackCardList(items: packs),
      ],
    );
  }
}

/// 给 HomeShell 用的 Actions（外层 AppBar 塞这个）
class ManagePageActions extends StatelessWidget {
  const ManagePageActions({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IconButton(
          tooltip: s.actionImport,
          onPressed: () async {
            try {
              await context.read<PackController>().install();
            } catch (_) {
              // 管理页不主动提示，避免噪音；需要的话下一步统一接入 Logger
            }
          },
          icon: const Icon(Icons.add),
        ),
        IconButton(
          tooltip: s.actionRefresh,
          onPressed: () async {
            await Future.wait(<Future<void>>[
              context.read<SourceController>().load(),
              context.read<PackController>().load(),
            ]);
          },
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme.titleMedium;
    return Row(
      children: <Widget>[
        Text(title, style: t),
        const SizedBox(width: 8),
        const Expanded(child: Divider(height: 1)),
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
    final isExtension = source.type == SourceType.extension;

    final typeLabel =
        isExtension ? s.manageSourceTypeExtension : s.manageSourceTypeRule;
    final subtitle = '$typeLabel • ${source.ref}';

    final cs = Theme.of(context).colorScheme;

    return ListTile(
      selected: selected,
      selectedColor: cs.primary,
      selectedTileColor: cs.primary.withOpacity(0.08),
      leading: Icon(isExtension ? Icons.extension : Icons.public),
      title: Text(source.name),
      subtitle: Text(
        subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: selected ? const Icon(Icons.check_circle) : null,
      onTap: () async {
        // 选中即写入全局 active，BrowsePage 会自动跟随
        await context.read<SourceStore>().setActive(source);
      },
    );
  }
}

class _PackCardList extends StatelessWidget {
  final List<EnginePack> items;
  const _PackCardList({required this.items});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          for (int i = 0; i < items.length; i++) ...<Widget>[
            _PackTile(pack: items[i]),
            if (i != items.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _PackTile extends StatelessWidget {
  final EnginePack pack;
  const _PackTile({required this.pack});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);

    final domainsText = pack.domains.isEmpty ? '-' : pack.domains.join(', ');
    final subtitle = '${pack.id} • v${pack.version}\n${s.managePackDomains}：$domainsText';

    return ListTile(
      leading: const Icon(Icons.extension),
      title: Text(pack.name),
      subtitle: Text(
        subtitle,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      trailing: IconButton(
        tooltip: s.managePackUninstall,
        icon: const Icon(Icons.delete_outline),
        onPressed: () async {
          try {
            await context.read<PackController>().uninstall(pack.id);
          } catch (_) {}
        },
      ),
    );
  }
}