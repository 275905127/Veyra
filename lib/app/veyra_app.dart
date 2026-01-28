import 'package:flutter/material.dart';

import '../gen_l10n/app_localizations.dart';
import '../features/home/home_shell.dart';

class VeyraApp extends StatelessWidget {
  const VeyraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,

      // i18n（使用 gen-l10n 生成的集合，最稳）
      localizationsDelegates: S.localizationsDelegates,
      supportedLocales: S.supportedLocales,

      // Theme
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorSchemeSeed: Colors.blueGrey,
      ),

      // App
      onGenerateTitle: (BuildContext ctx) => S.of(ctx).appName,
      home: const HomeShell(),
    );
  }
}