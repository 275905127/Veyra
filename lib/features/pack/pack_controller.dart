import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';

import '../../core/models/engine_pack.dart';
import '../../core/models/source.dart';
import '../../core/storage/pack_store.dart';
import '../source/source_controller.dart';

@singleton
class PackController extends ChangeNotifier {
  final PackStore packStore;
  final SourceController sourceController;

  PackController({
    required this.packStore,
    required this.sourceController,
  });

  final List<EnginePack> _packs = <EnginePack>[];
  List<EnginePack> get packs => List.unmodifiable(_packs);

  // ================================
  // public
  // ================================

  Future<void> load() async {
    _packs
      ..clear()
      ..addAll(await packStore.list());
    notifyListeners();
  }

  /// 安装引擎包 + 注册 sources
  Future<void> install() async {
    final manifest = await packStore.installFromPicker();
    if (manifest != null) {
      await _registerSourcesFromManifest(manifest);
    }
    await load();
    await sourceController.load();
  }

  Future<void> uninstall(String packId) async {
    await packStore.uninstall(packId);
    await load();
    await sourceController.load();
  }

  // ================================
  // 🔥 Editor API
  // ================================

  /// 读取 main.js
  Future<String> loadEntryCode(String packId) async {
    final manifest = await packStore.readManifest(packId);
    final entry = (manifest['entry'] ?? 'main.js').toString();
    return packStore.readText(packId, entry);
  }

  /// 保存 main.js
  Future<void> saveEntryCode(
    String packId,
    String code,
  ) async {
    final manifest = await packStore.readManifest(packId);
    final entry = (manifest['entry'] ?? 'main.js').toString();
    await packStore.writeTextWithBackup(packId, entry, code);
  }

  // ================================
  // core
  // ================================

  Future<void> _registerSourcesFromManifest(
    Map<String, dynamic> manifest,
  ) async {
    final sourcesRaw = manifest['sources'];
    if (sourcesRaw is! List) return;

    final store = sourceController.sourceStore;

    // ---- normalize sources ----
    final List<Map<String, dynamic>> sources = [];
    for (final e in sourcesRaw) {
      if (e is Map) {
        sources.add(e.cast<String, dynamic>());
      }
    }
    if (sources.isEmpty) return;

    // ---- pick primary ----
    Map<String, dynamic> primary = sources.first;
    for (final s in sources) {
      if (s['primary'] == true) {
        primary = s;
        break;
      }
    }

    final String packId = (manifest['id'] ?? '').toString().trim();
    if (packId.isEmpty) return;

    final String id = (primary['id'] ?? '').toString().trim();
    if (id.isEmpty) return;

    final String name =
        (primary['name'] ?? manifest['name'] ?? id).toString().trim();

    final String ref = (primary['ref'] ?? packId).toString().trim();

    // ============================
    // MODES
    // ============================

    final Map<String, String> modeLabelMap = {};

    // 1) primary.modes
    final pm = primary['modes'];
    if (pm is Map) {
      for (final e in pm.entries) {
        final k = e.key.toString().trim();
        final v = e.value.toString().trim();
        if (k.isNotEmpty) {
          modeLabelMap[k] = v.isEmpty ? k : v;
        }
      }
    }

    // 2) sources[].mode
    for (final s in sources) {
      final m = (s['mode'] ?? '').toString().trim();
      if (m.isEmpty) continue;
      final label = (s['name'] ?? m).toString().trim();
      modeLabelMap.putIfAbsent(
        m,
        () => label.isEmpty ? m : label,
      );
    }

    // 3) manifest.modes
    final mm = manifest['modes'];
    if (mm is Map) {
      for (final e in mm.entries) {
        final k = e.key.toString().trim();
        final v = e.value.toString().trim();
        if (k.isNotEmpty) {
          modeLabelMap.putIfAbsent(
            k,
            () => v.isEmpty ? k : v,
          );
        }
      }
    }

    if (modeLabelMap.isEmpty) {
      modeLabelMap['search'] = 'Search';
    }

    final String defaultMode =
        (primary['mode'] ?? '').toString().trim().isNotEmpty
            ? (primary['mode'] ?? '').toString().trim()
            : modeLabelMap.keys.first;

    // ============================
    // FILTER SCHEMA
    // ============================

    List<dynamic> filtersSchema = const [];

    final pf = primary['filters'];
    final sf = sources.first['filters'];
    final mf = manifest['filters'];

    if (pf is List) {
      filtersSchema = pf;
    } else if (sf is List) {
      filtersSchema = sf;
    } else if (mf is List) {
      filtersSchema = mf;
    }

    // ============================
    // FILTER UI
    // ============================

    Map<String, dynamic> filterUi = const {};

    final pUi = primary['filterUi'];
    final mUi = manifest['filterUi'];

    if (pUi is Map) {
      filterUi = pUi.cast<String, dynamic>();
    } else if (mUi is Map) {
      filterUi = mUi.cast<String, dynamic>();
    }

    // ============================
    // WRITE SOURCE
    // ============================

    await store.upsertSpecRaw(
      id: id,
      name: name,
      type: SourceType.extension,
      ref: ref,
      specRaw: {
        'packId': packId,
        'ref': ref,
        'defaultMode': defaultMode,
        'modes': modeLabelMap,
        'filters': filtersSchema,
        'filterUi': filterUi,
      },
    );

    // ============================
    // CLEAN OLD SOURCES
    // ============================

    final refs = await store.listRefs();
    for (final r in refs) {
      if (r.type != SourceType.extension) continue;
      if (r.id == id) continue;

      try {
        final raw = await store.getSpecRaw(r.id);
        final p = ((raw['packId'] ?? raw['pack']) ?? '').toString().trim();
        if (p == packId) {
          await store.remove(r.id);
        }
      } catch (_) {}
    }
  }
}