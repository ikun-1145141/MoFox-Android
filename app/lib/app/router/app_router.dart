import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/dashboard/presentation/dashboard_page.dart';
import '../../features/assistant/presentation/assistant_settings_page.dart';
import '../../features/file_manager/domain/rootfs_file_models.dart';
import '../../features/file_manager/presentation/instance_files_page.dart';
import '../../features/file_manager/presentation/text_file_editor_page.dart';
import '../../features/file_manager/presentation/toml_editor_page.dart';
import '../../features/home/presentation/home_page.dart';
import '../../features/instance/presentation/instance_detail_page.dart';
import '../../features/oobe/application/oobe_status_provider.dart';
import '../../features/oobe/presentation/oobe_page.dart';
import '../../features/settings/presentation/about_page.dart';
import '../../features/settings/presentation/appearance_page.dart';
import '../../features/settings/presentation/keepalive_status_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../../features/settings/presentation/third_party_licenses_page.dart';
import '../../features/shell/presentation/shell_page.dart';
import '../../features/terminal/presentation/terminal_page.dart';
import '../../features/instance/domain/instance.dart';
import '../../features/backup/presentation/backup_page.dart';
import '../../features/wizard/presentation/wizard_page.dart';

abstract final class AppRoute {
  static const String startup = '/startup';
  static const String oobe = '/oobe';
  static const String shell = '/';
  static const String home = '/home';
  static const String dashboard = '/dashboard';
  static const String instanceDetail = '/dashboard/instance';
  static const String instanceFiles = '/instance-files';
  static const String tomlEditor = '/toml-editor';
  static const String textEditor = '/text-editor';
  static const String terminal = '/terminal';
  static const String settings = '/settings';
  static const String appearance = '/settings/appearance';
  static const String assistantSettings = '/settings/assistant';
  static const String keepaliveStatus = '/settings/keepalive';
  static const String about = '/settings/about';
  static const String thirdPartyLicenses = '/settings/about/licenses';
  static const String wizard = '/wizard';
  static const String backup = '/settings/backup';
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final oobeStatus = ref.watch(oobeStatusProvider);
  return GoRouter(
    initialLocation: AppRoute.startup,
    redirect: (context, state) {
      final location = state.matchedLocation;
      if (oobeStatus.isLoading || oobeStatus.hasError) {
        return location == AppRoute.startup ? null : AppRoute.startup;
      }

      final oobeDone = oobeStatus.requireValue;
      if (location == AppRoute.startup) {
        return oobeDone ? AppRoute.home : AppRoute.oobe;
      }

      final goingToOobe = location == AppRoute.oobe;
      if (!oobeDone && !goingToOobe) return AppRoute.oobe;
      if (oobeDone && goingToOobe) return AppRoute.home;
      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: AppRoute.startup,
        builder: (_, __) => const _StartupGatePage(),
      ),
      GoRoute(
        path: AppRoute.oobe,
        builder: (_, __) => const OobePage(),
      ),
      // Wizard 是全屏 flow，不挂在 ShellRoute 下面（避免被底栏挤）。
      GoRoute(
        path: AppRoute.wizard,
        builder: (_, state) {
          final extra = state.extra;
          return WizardPage(
            resumeInstance: extra is Instance ? extra : null,
          );
        },
      ),
      GoRoute(
        path: AppRoute.about,
        builder: (_, __) => const AboutPage(),
      ),
      GoRoute(
        path: AppRoute.keepaliveStatus,
        builder: (_, __) => const KeepaliveStatusPage(),
      ),
      GoRoute(
        path: AppRoute.appearance,
        builder: (_, __) => const AppearancePage(),
      ),
      GoRoute(
        path: AppRoute.assistantSettings,
        builder: (_, __) => const AssistantSettingsPage(),
      ),
      GoRoute(
        path: AppRoute.backup,
        builder: (_, __) => const BackupPage(),
      ),
      GoRoute(
        path: AppRoute.thirdPartyLicenses,
        builder: (_, __) => const ThirdPartyLicensesPage(),
      ),
      GoRoute(
        path: AppRoute.instanceDetail,
        pageBuilder: (_, state) {
          final extra = state.extra;
          if (extra is! Instance) {
            return const MaterialPage(
              key: ValueKey('instanceDetail-error'),
              child: _RouteArgsErrorPage(
                message: '实例参数缺失，请从实例列表进入。',
              ),
            );
          }
          final instance = extra;
          return MaterialPage(
            key: ValueKey('instanceDetail-${instance.id}'),
            child: InstanceDetailPage(instance: instance),
          );
        },
      ),
      GoRoute(
        path: AppRoute.instanceFiles,
        pageBuilder: (_, state) {
          final extra = state.extra;
          if (extra is! InstanceFilesRouteArgs) {
            return MaterialPage(
              key: const ValueKey('instanceFiles-error'),
              child: const _RouteArgsErrorPage(
                message: '文件页参数缺失，请从实例详情进入。',
              ),
            );
          }
          return MaterialPage(
            key: ValueKey('instanceFiles-${extra.scope.id}'),
            child: InstanceFilesPage(args: extra),
          );
        },
      ),
      GoRoute(
        path: AppRoute.tomlEditor,
        pageBuilder: (_, state) {
          final extra = state.extra;
          if (extra is! TomlEditorRouteArgs) {
            return MaterialPage(
              key: const ValueKey('tomlEditor-error'),
              child: const _RouteArgsErrorPage(
                message: '编辑器参数缺失，请从文件管理页进入。',
              ),
            );
          }
          return MaterialPage(
            key: ValueKey(
              'tomlEditor-${extra.scope.id}-${extra.relativePath.displayPath}',
            ),
            child: TomlEditorPage(args: extra),
          );
        },
      ),
      GoRoute(
        path: AppRoute.textEditor,
        pageBuilder: (_, state) {
          final extra = state.extra;
          if (extra is! TextFileEditorRouteArgs) {
            return MaterialPage(
              key: const ValueKey('textEditor-error'),
              child: const _RouteArgsErrorPage(
                message: '编辑器参数缺失，请从文件管理页进入。',
              ),
            );
          }
          return MaterialPage(
            key: ValueKey(
              'textEditor-${extra.scope.id}-${extra.relativePath.displayPath}',
            ),
            child: TextFileEditorPage(args: extra),
          );
        },
      ),
      GoRoute(
        path: AppRoute.shell,
        redirect: (_, __) => AppRoute.home,
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => ShellPage(
          navigationShell: navigationShell,
        ),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoute.home,
                builder: (_, __) => const HomePage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoute.dashboard,
                builder: (_, __) => const DashboardPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoute.terminal,
                builder: (_, state) {
                  final extra = state.extra;
                  final values = extra is Map<String, String> ? extra : null;
                  return TerminalPage(
                    cwd: values?['cwd'] ?? '/root',
                    title: values?['title'] ?? '终端',
                    instanceId: values?['instanceId'],
                  );
                },
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoute.settings,
                builder: (_, __) => const SettingsPage(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

class _StartupGatePage extends ConsumerWidget {
  const _StartupGatePage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(oobeStatusProvider);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: status.when(
              loading: () => Semantics(
                label: '正在加载应用设置',
                liveRegion: true,
                child: const CircularProgressIndicator(),
              ),
              data: (_) => const CircularProgressIndicator(),
              error: (_, __) => Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.settings_backup_restore_outlined,
                    size: 48,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '无法读取启动设置',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '请重试；你的实例和文件不会被修改。',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => ref.invalidate(oobeStatusProvider),
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 路由参数类型不匹配时显示的兜底页。
class _RouteArgsErrorPage extends StatelessWidget {
  const _RouteArgsErrorPage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('打开失败')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(message, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}
