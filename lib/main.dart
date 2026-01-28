import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app/veyra_app.dart';
import 'core/di/injection.dart';
import 'core/log/logger_store.dart';
import 'core/services/wallpaper_service.dart';
import 'core/storage/api_key_store.dart';
import 'core/storage/pack_store.dart';
import 'core/storage/source_store.dart';
import 'features/pack/pack_controller.dart';
import 'features/source/source_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. 初始化依赖注入（包括各种 Store 的 init）
  await configureDependencies();

  final logger = getIt<LoggerStore>();

  // Global errors -> logger
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    logger.e(
      'FlutterError',
      details.exceptionAsString(),
      details: details.stack?.toString(),
    );
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    logger.e('PlatformError', error.toString(), details: stack.toString());
    return true;
  };

  runApp(
    MultiProvider(
      providers: [
        // Services
        Provider<WallpaperService>.value(value: getIt<WallpaperService>()),
        Provider<PackStore>.value(value: getIt<PackStore>()),

        // Stores
        ChangeNotifierProvider<SourceStore>.value(value: getIt<SourceStore>()),
        ChangeNotifierProvider<LoggerStore>.value(value: logger),
        ChangeNotifierProvider<ApiKeyStore>.value(value: getIt<ApiKeyStore>()),

        // Controllers
        ChangeNotifierProvider<SourceController>.value(value: getIt<SourceController>()),
        ChangeNotifierProvider<PackController>.value(value: getIt<PackController>()),
      ],
      child: const _Bootstrap(child: VeyraApp()),
    ),
  );
}

/// 启动引导：统一触发一次数据加载
class _Bootstrap extends StatefulWidget {
  final Widget child;
  const _Bootstrap({required this.child});

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.wait(<Future<void>>[
        context.read<SourceController>().load(),
        context.read<PackController>().load(),
      ]);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}