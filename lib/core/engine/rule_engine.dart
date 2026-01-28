import 'package:injectable/injectable.dart';

import '../models/source_spec.dart';
import '../models/uni_wallpaper.dart';
import 'engine_registry.dart';

class RuleEngineContext {
  // ✅ 1. 恢复为空，我们在 UI 层根据 URL 动态生成
  Map<String, String> get commonImageHeaders => const <String, String>{};
}

@singleton
class RuleEngine {
  final EngineRegistry registry;
  final RuleEngineContext ctx = RuleEngineContext();

  RuleEngine({required this.registry});

  Future<List<UniWallpaper>> fetchByKey({
    required String engineKey,
    required SourceSpec spec,
    required int page,
    String? keyword,
    Map<String, dynamic>? filters,
  }) async {
    return const <UniWallpaper>[];
  }
}
