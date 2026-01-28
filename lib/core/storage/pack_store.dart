import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/engine_pack.dart';

/// 引擎包存储：
/// - install: 选择 zip / .enginepack
/// - 解压到 app 私有目录
/// - 保存 packs 索引到 SharedPreferences
///
/// 约定：pack 根目录必须包含 manifest.json
/// manifest.json 示例：
/// {
///   "id": "wallhaven_pack",
///   "name": "Wallhaven Engine",
///   "version": "1.0.0",
///   "entry": "main.js",
///   "permissions": { "domains": ["wallhaven.cc"] },
///   "sources": [
///     { "id": "wallhaven", "name": "Wallhaven", "ref": "wallhaven" }
///   ]
/// }
class PackStore {
  static const String _kIndex = 'engine_packs_index';

  late SharedPreferences _prefs;
  late Directory _root;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final dir = await getApplicationSupportDirectory();
    _root = Directory('${dir.path}/enginepacks');
    if (!await _root.exists()) {
      await _root.create(recursive: true);
    }
  }

  Future<List<EnginePack>> list() async {
    final raw = _prefs.getString(_kIndex);
    if (raw == null || raw.isEmpty) return const <EnginePack>[];

    final decoded = jsonDecode(raw);
    if (decoded is! List) return const <EnginePack>[];

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

  /// 安装：从文件选择器挑选 zip / enginepack 并解压。
  ///
  /// 返回 manifest 原始 Map（便于上层写 SourceStore）
  Future<Map<String, dynamic>?> installFromPicker() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['zip', 'enginepack'],
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
        final content = utf8.decode(f.content as List<int>);
        final obj = jsonDecode(content);
        if (obj is Map) {
          manifest = obj.cast<String, dynamic>();
          break;
        }
      }
    }
    if (manifest == null) {
      throw Exception('manifest.json not found in pack');
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

    // 解压所有文件到 target
    for (final f in archive.files) {
      if (!f.isFile) continue;
      final out = File('${target.path}/${f.name}');
      await out.parent.create(recursive: true);
      await out.writeAsBytes(f.content as List<int>, flush: true);
    }

    // 写入索引
    final packs = (await list()).where((p) => p.id != pack.id).toList()
      ..add(pack);
    await _saveIndex(packs);

    return manifest;
  }

  Future<void> uninstall(String packId) async {
    final target = Directory('${_root.path}/$packId');
    if (await target.exists()) {
      await target.delete(recursive: true);
    }

    final packs = (await list()).where((p) => p.id != packId).toList();
    await _saveIndex(packs);
  }

  Future<File> resolveEntry(String packId, String entry) async {
    final f = File('${_root.path}/$packId/$entry');
    if (!await f.exists()) {
      throw Exception('Pack not installed: $packId/$entry');
    }
    return f;
  }

  /// 读取已安装引擎包的 manifest（用于恢复 sources / 调试）
  Future<Map<String, dynamic>> readManifest(String packId) async {
    final f = File('${_root.path}/$packId/manifest.json');
    if (!await f.exists()) {
      throw Exception('manifest.json not found: $packId');
    }
    final txt = await f.readAsString();
    final obj = jsonDecode(txt);
    if (obj is Map<String, dynamic>) return obj;
    if (obj is Map) return obj.cast<String, dynamic>();
    throw Exception('invalid manifest.json: $packId');
  }
}