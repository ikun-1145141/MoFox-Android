import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';

/// 顶层壳：底部 NavigationBar（< 600 dp）+ 侧边 NavigationRail（≥ 600 dp）。
///
/// 标题与 leading 由各 page 自己管，shell 只负责导航容器。
class ShellPage extends StatelessWidget {
  const ShellPage({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final tab = _tabFromLocation(location);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 600;
        if (wide) {
          return Scaffold(
            body: SafeArea(
              child: Row(
                children: <Widget>[
                  NavigationRail(
                    selectedIndex: tab,
                    onDestinationSelected: (i) => _go(context, i),
                    labelType: NavigationRailLabelType.all,
                    destinations: const <NavigationRailDestination>[
                      NavigationRailDestination(
                        icon: Icon(Icons.dashboard_outlined),
                        selectedIcon: Icon(Icons.dashboard),
                        label: Text('管理'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.terminal_outlined),
                        selectedIcon: Icon(Icons.terminal),
                        label: Text('终端'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.settings_outlined),
                        selectedIcon: Icon(Icons.settings),
                        label: Text('设置'),
                      ),
                    ],
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: child),
                ],
              ),
            ),
          );
        }
        return Scaffold(
          body: child,
          bottomNavigationBar: NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: (i) => _go(context, i),
            destinations: const <NavigationDestination>[
              NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: '管理',
              ),
              NavigationDestination(
                icon: Icon(Icons.terminal_outlined),
                selectedIcon: Icon(Icons.terminal),
                label: '终端',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: '设置',
              ),
            ],
          ),
        );
      },
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
