import 'package:injectable/injectable.dart';

import '../log/logger_store.dart';
import '../storage/api_key_store.dart';
import '../storage/pack_store.dart';
import '../storage/source_store.dart';
import '../engine/engine_registry.dart';

@module
abstract class RegisterModule {
  // LoggerStore
  @singleton
  @preResolve
  Future<LoggerStore> get loggerStore async {
    final store = LoggerStore();
    await store.init();
    return store;
  }

  // PackStore
  @singleton
  @preResolve
  Future<PackStore> get packStore async {
    final store = PackStore();
    await store.init();
    return store;
  }

  // SourceStore
  @singleton
  @preResolve
  Future<SourceStore> get sourceStore async {
    final store = SourceStore();
    await store.init();
    return store;
  }

  // ApiKeyStore
  @singleton
  @preResolve
  Future<ApiKeyStore> get apiKeyStore async {
    final store = ApiKeyStore();
    await store.init();
    return store;
  }

  // EngineRegistry
  @singleton
  EngineRegistry get engineRegistry => EngineRegistry.bootstrapDefault();
}
