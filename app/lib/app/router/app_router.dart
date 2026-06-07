import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/oobe/application/oobe_status_provider.dart';
import '../../features/oobe/presentation/oobe_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../../features/shell/presentation/shell_page.dart';
import '../../features/terminal/presentation/terminal_page.dart';
import '../../features/webview/presentation/webview_page.dart';

abstract final class AppRoute {
  static const String oobe = '/oobe';
  static const String shell = '/';
  static const String webview = 'webview';
  static const String terminal = 'terminal';
  static const String settings = 'settings';
}

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoute.shell,
    redirect: (context, state) {
      final oobeDone = ref.read(oobeStatusProvider).valueOrNull ?? false;
      final goingToOobe = state.matchedLocation == AppRoute.oobe;
      if (!oobeDone && !goingToOobe) return AppRoute.oobe;
      if (oobeDone && goingToOobe) return AppRoute.shell;
      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: AppRoute.oobe,
        builder: (_, __) => const OobePage(),
      ),
      ShellRoute(
        builder: (context, state, child) => ShellPage(child: child),
        routes: <RouteBase>[
          GoRoute(
            path: AppRoute.shell,
            redirect: (_, __) => '/${AppRoute.webview}',
          ),
          GoRoute(
            path: '/${AppRoute.webview}',
            builder: (_, __) => const WebViewPage(),
          ),
          GoRoute(
            path: '/${AppRoute.terminal}',
            builder: (_, __) => const TerminalPage(),
          ),
          GoRoute(
            path: '/${AppRoute.settings}',
            builder: (_, __) => const SettingsPage(),
          ),
        ],
      ),
    ],
  );
});
