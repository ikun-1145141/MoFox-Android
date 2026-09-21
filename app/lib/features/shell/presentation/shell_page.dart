import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';

/// 顶层壳：底部 NavigationBar（< 600 dp）+ 侧边 NavigationRail（≥ 600 dp）。
///
/// Tab 顺序：首页 → 管理 → 终端 → 设置。
class ShellPage extends StatelessWidget {
  const ShellPage({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final tab = navigationShell.currentIndex;

    return PopScope(
      canPop: context.canPop() || tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || tab == 0) return;
        context.go(AppRoute.home);
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 600;
          if (wide) {
            final expanded = constraints.maxWidth >= 1200;
            return Scaffold(
              body: SafeArea(
                child: Row(
                  children: <Widget>[
                    NavigationRail(
                      extended: expanded,
                      minExtendedWidth: 220,
                      selectedIndex: tab,
                      onDestinationSelected: (i) => _go(context, i),
                      labelType: expanded
                          ? NavigationRailLabelType.none
                          : NavigationRailLabelType.all,
                      groupAlignment: -0.82,
                      leading: Padding(
                        padding: EdgeInsets.fromLTRB(
                          expanded ? 20 : 8,
                          12,
                          expanded ? 20 : 8,
                          20,
                        ),
                        child: expanded
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  const _BrandMark(),
                                  const SizedBox(width: 12),
                                  Text(
                                    'MoFox',
                                    style:
                                        Theme.of(context).textTheme.titleLarge,
                                  ),
                                ],
                              )
                            : const _BrandMark(),
                      ),
                      destinations: const <NavigationRailDestination>[
                        NavigationRailDestination(
                          icon: Icon(Icons.home_outlined),
                          selectedIcon: Icon(Icons.home),
                          label: Text('概览'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.dashboard_outlined),
                          selectedIcon: Icon(Icons.dashboard),
                          label: Text('实例'),
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
                    Expanded(child: navigationShell),
                  ],
                ),
              ),
            );
          }
          return Scaffold(
            body: navigationShell,
            bottomNavigationBar: NavigationBar(
              selectedIndex: tab,
              onDestinationSelected: (i) => _go(context, i),
              destinations: const <NavigationDestination>[
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: '概览',
                ),
                NavigationDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  selectedIcon: Icon(Icons.dashboard),
                  label: '实例',
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
      ),
    );
  }

  void _go(BuildContext context, int i) {
    navigationShell.goBranch(
      i,
      initialLocation: i == navigationShell.currentIndex,
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'MoFox',
      image: true,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(
            Icons.auto_awesome_rounded,
            size: 24,
            color: scheme.onPrimaryContainer,
          ),
        ),
      ),
    );
  }
}
