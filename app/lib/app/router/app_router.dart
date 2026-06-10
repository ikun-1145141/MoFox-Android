import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/dashboard/presentation/dashboard_page.dart';
import '../../features/oobe/application/oobe_status_provider.dart';
import '../../features/oobe/presentation/oobe_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../../features/shell/presentation/shell_page.dart';
import '../../features/terminal/presentation/terminal_page.dart';
import '../../features/webview/presentation/webview_page.dart';
import '../../features/wizard/presentation/wizard_page.dart';

abstract final class AppRoute {
  static const String oobe = '/oobe';
  static const String shell = '/';
  static const String dashboard = '/dashboard';
  static const String webview = '/webview';
  static const String terminal = '/terminal';
  static const String settings = '/settings';
  static const String wizard = '/wizard';
}

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoute.dashboard,
    redirect: (context, state) {
      final status = ref.watch(oobeStatusProvider);
      final oobeDone = status.valueOrNull;
      if (oobeDone == null) return null;

      final goingToOobe = state.matchedLocation == AppRoute.oobe;
      if (!oobeDone && !goingToOobe) return AppRoute.oobe;
      if (oobeDone && goingToOobe) return AppRoute.dashboard;
      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: AppRoute.oobe,
        builder: (_, __) => const OobePage(),
      ),
      // Wizard 是全屏 flow，不挂在 ShellRoute 下面（避免被底栏挤）。
      GoRoute(
        path: AppRoute.wizard,
        builder: (_, __) => const WizardPage(),
      ),
      ShellRoute(
        builder: (context, state, child) => ShellPage(child: child),
        routes: <RouteBase>[
          GoRoute(
            path: AppRoute.shell,
            redirect: (_, __) => AppRoute.dashboard,
          ),
          GoRoute(
            path: AppRoute.dashboard,
            builder: (_, __) => const DashboardPage(),
          ),
          GoRoute(
            path: AppRoute.webview,
            builder: (_, __) => const WebViewPage(),
          ),
          GoRoute(
            path: AppRoute.terminal,
            builder: (_, state) {
              final extra = state.extra as Map<String, String>?;
              return TerminalPage(
                cwd: extra?['cwd'] ?? '/root',
                title: extra?['title'] ?? '终端',
              );
            },
          ),
          GoRoute(
            path: AppRoute.settings,
            builder: (_, __) => const SettingsPage(),
          ),
        ],
      ),
    ],
  );
});
