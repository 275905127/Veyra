import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/log/logger_store.dart';
import '../../gen_l10n/app_localizations.dart';
import 'log_viewer_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final logger = context.watch<LoggerStore>();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: <Widget>[
        // =========================
        // General
        // =========================
        _SectionHeader(title: s.settingsSectionGeneral),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.cleaning_services_outlined),
                title: Text(s.settingsClearCache),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  logger.i('Settings', 'clearCache tapped');
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // =========================
        // Debug
        // =========================
        _SectionHeader(title: s.settingsSectionDebug),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: <Widget>[
              SwitchListTile(
                secondary: const Icon(Icons.bug_report_outlined),
                title: Text(s.settingsEnableLogs),
                value: logger.enabled,
                onChanged: (bool v) async {
                  await logger.setEnabled(v);
                  logger.i('Settings', 'logger enabled=$v');
                },
              ),
              ListTile(
                leading: const Icon(Icons.article_outlined),
                title: const Text('查看日志'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LogViewerPage()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('清空日志'),
                onTap: logger.clear,
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // =========================
        // About
        // =========================
        _SectionHeader(title: s.settingsSectionAbout),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(s.appName),
                subtitle: Text('${s.settingsVersion} 0.1.0'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme.titleMedium;
    return Row(
      children: <Widget>[
        Text(title, style: t),
        const SizedBox(width: 8),
        const Expanded(child: Divider(height: 1)),
      ],
    );
  }
}