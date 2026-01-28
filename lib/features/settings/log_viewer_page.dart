import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/log/logger_store.dart';

class LogViewerPage extends StatelessWidget {
  const LogViewerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LoggerStore>();
    final items = store.items.reversed.toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('日志'),
        actions: <Widget>[
          IconButton(
            tooltip: '清空',
            icon: const Icon(Icons.delete_outline),
            onPressed: store.clear,
          ),
        ],
      ),
      body: items.isEmpty
          ? const Center(child: Text('暂无日志'))
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 12),
              itemBuilder: (context, i) {
                final e = items[i];
                final title = '[${e.level.name}] ${e.tag}';
                final time = e.time.toIso8601String().replaceFirst('T', ' ');
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(title),
                  subtitle: Text(
                    '$time\n${e.message}${e.details == null ? '' : '\n${e.details}'}',
                  ),
                );
              },
            ),
    );
  }
}