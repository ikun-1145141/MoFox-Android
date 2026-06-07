import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';

class ShellPage extends StatelessWidget {
  const ShellPage({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final tab = _tabFromLocation(location);
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => _go(context, i),
        destinations: const <NavigationDestination>[
          NavigationDestination(icon: Icon(Icons.web_outlined), selectedIcon: Icon(Icons.web), label: '管理'),
          NavigationDestination(icon: Icon(Icons.terminal_outlined), selectedIcon: Icon(Icons.terminal), label: '终端'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: '设置'),
        ],
      ),
    );
  }

  int _tabFromLocation(String loc) {
    if (loc.startsWith('/${AppRoute.terminal}')) return 1;
    if (loc.startsWith('/${AppRoute.settings}')) return 2;
    return 0;
  }

  void _go(BuildContext context, int i) {
    final route = switch (i) {
      1 => '/${AppRoute.terminal}',
      2 => '/${AppRoute.settings}',
      _ => '/${AppRoute.webview}',
    };
    context.go(route);
  }
}
