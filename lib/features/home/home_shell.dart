import 'package:flutter/material.dart';

import '../../gen_l10n/app_localizations.dart';
import '../browse/browse_page.dart';
import '../manage/manage_page.dart';
import '../settings/settings_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);

    const pages = <Widget>[
      BrowsePage(),
      ManagePage(),
      SettingsPage(),
    ];

    final titles = <String>[
      s.tabBrowse,
      s.tabManage,
      s.tabSettings,
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_index]),
        actions: <Widget>[
          if (_index == 0)
            IconButton(
              tooltip: s.actionSearch,
              icon: const Icon(Icons.search),
              onPressed: () {
                // TODO: 接入搜索（后续 SearchDelegate）
              },
            )
          else if (_index == 1)
            const ManagePageActions(),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: <NavigationDestination>[
          NavigationDestination(
            icon: const Icon(Icons.photo_library_outlined),
            selectedIcon: const Icon(Icons.photo_library),
            label: s.tabBrowse,
          ),
          NavigationDestination(
            icon: const Icon(Icons.extension_outlined),
            selectedIcon: const Icon(Icons.extension),
            label: s.tabManage,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: s.tabSettings,
          ),
        ],
      ),
    );
  }
}