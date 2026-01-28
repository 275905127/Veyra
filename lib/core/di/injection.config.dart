// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// **************************************************************************
// InjectableConfigGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:get_it/get_it.dart' as _i174;
import 'package:injectable/injectable.dart' as _i526;

import '../../features/pack/pack_controller.dart' as _i1055;
import '../../features/source/source_controller.dart' as _i680;
import '../engine/engine_registry.dart' as _i941;
import '../engine/rule_engine.dart' as _i959;
import '../extension/extension_engine.dart' as _i22;
import '../log/logger_store.dart' as _i948;
import '../services/wallpaper_service.dart' as _i1041;
import '../storage/api_key_store.dart' as _i914;
import '../storage/pack_store.dart' as _i936;
import '../storage/source_store.dart' as _i1032;
import 'register_module.dart' as _i291;

extension GetItInjectableX on _i174.GetIt {
// initializes the registration of main-scope dependencies inside of GetIt
  Future<_i174.GetIt> init({
    String? environment,
    _i526.EnvironmentFilter? environmentFilter,
  }) async {
    final gh = _i526.GetItHelper(
      this,
      environment,
      environmentFilter,
    );
    final registerModule = _$RegisterModule();
    await gh.singletonAsync<_i948.LoggerStore>(
      () => registerModule.loggerStore,
      preResolve: true,
    );
    await gh.singletonAsync<_i936.PackStore>(
      () => registerModule.packStore,
      preResolve: true,
    );
    await gh.singletonAsync<_i1032.SourceStore>(
      () => registerModule.sourceStore,
      preResolve: true,
    );
    await gh.singletonAsync<_i914.ApiKeyStore>(
      () => registerModule.apiKeyStore,
      preResolve: true,
    );
    gh.singleton<_i941.EngineRegistry>(() => registerModule.engineRegistry);
    gh.singleton<_i680.SourceController>(() => _i680.SourceController(
          sourceStore: gh<_i1032.SourceStore>(),
          packStore: gh<_i936.PackStore>(),
        ));
    gh.singleton<_i22.ExtensionEngine>(() => _i22.ExtensionEngine(
          packStore: gh<_i936.PackStore>(),
          apiKeyStore: gh<_i914.ApiKeyStore>(),
          logger: gh<_i948.LoggerStore>(),
        ));
    gh.singleton<_i959.RuleEngine>(
        () => _i959.RuleEngine(registry: gh<_i941.EngineRegistry>()));
    gh.singleton<_i1041.WallpaperService>(() => _i1041.WallpaperService(
          ruleEngine: gh<_i959.RuleEngine>(),
          packStore: gh<_i936.PackStore>(),
          extensionEngine: gh<_i22.ExtensionEngine>(),
          apiKeyStore: gh<_i914.ApiKeyStore>(),
          logger: gh<_i948.LoggerStore>(),
        ));
    gh.singleton<_i1055.PackController>(() => _i1055.PackController(
          packStore: gh<_i936.PackStore>(),
          sourceController: gh<_i680.SourceController>(),
        ));
    return this;
  }
}

class _$RegisterModule extends _i291.RegisterModule {}
