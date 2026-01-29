import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/engine_pack.dart';

class PackStore {
  static const String _kIndex = 'engine_packs_index';

  late SharedPreferences _prefs;
  late Directory _root;

  // =========================
  // init
  // =========================

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final dir = await getApplicationSupportDirectory();
    _root = Directory('${dir.path}/enginepacks');
    if (!await _root.exists()) {
      await _root.create(recursive: true);
    }
  }

  // =========================
  // list
  // =========================

  Future<List<EnginePack>> list() async {
    final raw = _prefs.getString(_kIndex);
    if (raw == null || raw.isEmpty) return const [];

    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];

    final packs = decoded
        .whereType<Map>()
        .map((m) => EnginePack.fromMap(m.cast<String, dynamic>()))
        .toList();

    packs.sort((a, b) => a.name.compareTo(b.name));
    return packs;
  }

  Future<void> _saveIndex(List<EnginePack> packs) async {
    await _prefs.setString(
      _kIndex,
      jsonEncode(packs.map((e) => e.toMap()).toList()),
    );
  }

  // =========================
  // install
  // =========================

  Future<Map<String, dynamic>?> installFromPicker() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip', 'enginepack'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;

    final file = result.files.first;
    if (file.bytes == null) {
      throw Exception('file bytes unavailable');
    }

    final archive = ZipDecoder().decodeBytes(file.bytes!);

    Map<String, dynamic>? manifest;
    for (final f in archive.files) {
      if (f.isFile && f.name.endsWith('manifest.json')) {
        final txt = utf8.decode(f.content as List<int>);
        final obj = jsonDecode(txt);
        if (obj is Map) {
          manifest = obj.cast<String, dynamic>();
          break;
        }
      }
    }

    if (manifest == null) {
      throw Exception('manifest.json not found');
    }

    final pack = EnginePack.fromManifest(manifest);
    if (pack.id.trim().isEmpty) {
      throw Exception('pack id empty');
    }

    final target = Directory('${_root.path}/${pack.id}');
    if (await target.exists()) {
      await target.delete(recursive: true);
    }
    await target.create(recursive: true);

    for (final f in archive.files) {
      if (!f.isFile) continue;
      final out = File('${target.path}/${f.name}');
      await out.parent.create(recursive: true);
      await out.writeAsBytes(f.content as List<int>, flush: true);
    }

    final packs = (await list()).where((p) => p.id != pack.id).toList()
      ..add(pack);
    await _saveIndex(packs);

    return manifest;
  }

  // =========================
  // uninstall
  // =========================

  Future<void> uninstall(String packId) async {
    final dir = Directory('${_root.path}/$packId');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }

    final packs = (await list()).where((p) => p.id != packId).toList();
    await _saveIndex(packs);
  }

  // =========================
  // resolve entry
  // =========================

  Future<File> resolveEntry(String packId, String entry) async {
    final f = File('${_root.path}/$packId/$entry');
    if (!await f.exists()) {
      throw Exception('Pack not installed: $packId/$entry');
    }
    return f;
  }

  // =========================
  // manifest
  // =========================

  Future<Map<String, dynamic>> readManifest(String packId) async {
    final f = File('${_root.path}/$packId/manifest.json');
    if (!await f.exists()) {
      throw Exception('manifest.json not found: $packId');
    }

    final txt = await f.readAsString();
    final obj = jsonDecode(txt);
    if (obj is Map<String, dynamic>) return obj;
    if (obj is Map) return obj.cast<String, dynamic>();
    throw Exception('invalid manifest.json');
  }

  // =====================================================
  // ================= EDITOR SUPPORT ====================
  // =====================================================

  /// pack 根目录
  Future<Directory> getPackDir(String packId) async {
    final d = Directory('${_root.path}/$packId');
    if (!await d.exists()) {
      throw Exception('pack not installed: $packId');
    }
    return d;
  }

  /// 读取任意文本文件
  Future<String> readText(String packId, String relativePath) async {
    final file = File('${_root.path}/$packId/$relativePath');
    if (!await file.exists()) {
      throw Exception('file not found: $relativePath');
    }
    return file.readAsString();
  }

  /// 写文本 + 自动备份
  Future<void> writeTextWithBackup(
    String packId,
    String relativePath,
    String content, {
    int keep = 5,
  }) async {
    final file = File('${_root.path}/$packId/$relativePath');
    await file.parent.create(recursive: true);

    final bakDir =
        Directory('${_root.path}/$packId/.bak');
    if (!await bakDir.exists()) {
      await bakDir.create(recursive: true);
    }

    if (await file.exists()) {
      final ts =
          DateTime.now().millisecondsSinceEpoch.toString();
      final name = relativePath.split('/').last;
      final bak =
          File('${bakDir.path}/$name.$ts.bak');
      await file.copy(bak.path);

      final backups = bakDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains(name))
          .toList()
        ..sort((a, b) =>
            b.lastModifiedSync()
                .compareTo(a.lastModifiedSync()));

      for (final f in backups.skip(keep)) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }

    await file.writeAsString(content, flush: true);
  }
}