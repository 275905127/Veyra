import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';

import 'injection.config.dart';

// 全局 Service Locator
final GetIt getIt = GetIt.instance;

@InjectableInit(
  initializerName: 'init', // 默认是 init
  preferRelativeImports: true, // 建议使用相对路径
  asExtension: true, // 生成为 GetIt 的扩展方法
)
Future<void> configureDependencies() => getIt.init();
