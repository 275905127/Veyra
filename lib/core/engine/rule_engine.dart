import 'package:injectable/injectable.dart';

import '../models/source_spec.dart';
import '../models/uni_wallpaper.dart';
import 'engine_registry.dart';

class RuleEngineContext {
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
    // stub: 先返回空，后面我们再接真正 RuleEngine
    return const <UniWallpaper>[];
  }
}