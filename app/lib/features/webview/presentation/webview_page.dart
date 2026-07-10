import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../dashboard/application/process_console_provider.dart';
import '../../instance/application/instance_repository.dart';
import '../../instance/domain/instance.dart';
import '../application/webview_notifier.dart';

enum WebUiTarget { neoMofox, napcat }

extension on WebUiTarget {
  String get label => switch (this) {
        WebUiTarget.neoMofox => 'Neo-MoFox',
        WebUiTarget.napcat => 'NapCat',
      };
  IconData get icon => switch (this) {
        WebUiTarget.neoMofox => Icons.dashboard_outlined,
        WebUiTarget.napcat => Icons.qr_code_2_outlined,
      };
  IconData get selectedIcon => switch (this) {
        WebUiTarget.neoMofox => Icons.dashboard,
        WebUiTarget.napcat => Icons.qr_code_2,
      };
}

class WebViewPage extends ConsumerStatefulWidget {
  const WebViewPage({super.key});
  @override
  ConsumerState<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends ConsumerState<WebViewPage> {
  WebUiTarget _target = WebUiTarget.neoMofox;
  String? _selectedInstanceId;
  bool _loadedForInstanceId = false;
  String? _loadedNapcatUrl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final asyncInstances = ref.watch(instancesProvider);
    final instances = asyncInstances.valueOrNull ?? <Instance>[];
    final webuiInstances =
        instances.where((i) => i.installWebui).toList(growable: false);
    final napcatInstances =
        instances.where((i) => i.installNapcat).toList(growable: false);

    // 当前 target 可选的实例列表
    final candidates =
        _target == WebUiTarget.neoMofox ? webuiInstances : napcatInstances;

    // 选中的实例
    Instance? selected;
    if (candidates.isNotEmpty) {
      selected = candidates.firstWhere(
        (i) => i.id == _selectedInstanceId,
        orElse: () => candidates.first,
      );
    }

    final processState = ref.watch(processConsoleProvider);
    final botRunning = processState.botStatus == 'running';
    final napcatRunning = processState.napcatStatus == 'running';
    final napcatWebuiUrl = processState.napcatWebuiUrl;

    final controller = ref.watch(webviewNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(selected?.name ?? '管理'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            onPressed: () =>
                ref.read(webviewNotifierProvider.notifier).reload(),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: '在浏览器打开',
            onPressed: () {
              final url = _target == WebUiTarget.neoMofox
                  ? 'http://127.0.0.1:8000/webui/frontend'
                  : napcatWebuiUrl;
              if (url != null && url.isNotEmpty) {
                ref.read(webviewNotifierProvider.notifier).openInBrowser(url);
              }
            },
            icon: const Icon(Icons.open_in_new),
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(candidates.length > 1 ? 100 : 64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // 实例选择器（多于 1 个实例时显示）
                if (candidates.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: DropdownMenu<String>(
                      expandedInsets: EdgeInsets.zero,
                      initialSelection: selected?.id,
                      label: const Text('实例'),
                      onSelected: (value) {
                        if (value != null) {
                          setState(() {
                            _selectedInstanceId = value;
                            _loadedForInstanceId = false;
                          });
                        }
                      },
                      dropdownMenuEntries: <DropdownMenuEntry<String>>[
                        for (final i in candidates)
                          DropdownMenuEntry<String>(
                            value: i.id,
                            label: i.name,
                          ),
                      ],
                    ),
                  ),
                SegmentedButton<WebUiTarget>(
                  segments: <ButtonSegment<WebUiTarget>>[
                    for (final t in WebUiTarget.values)
                      ButtonSegment(
                        value: t,
                        label: Text(t.label),
                        icon: Icon(t.icon),
                      ),
                  ],
                  selected: <WebUiTarget>{_target},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() {
                    _target = s.first;
                    _selectedInstanceId = null;
                    _loadedForInstanceId = false;
                    _loadedNapcatUrl = null;
                  }),
                ),
              ],
            ),
          ),
        ),
      ),
      body: ColoredBox(
        color: scheme.surface,
        child: _buildBody(
          context,
          controller: controller,
          selected: selected,
          botRunning: botRunning,
          napcatRunning: napcatRunning,
          napcatWebuiUrl: napcatWebuiUrl,
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context, {
    required WebViewController controller,
    required Instance? selected,
    required bool botRunning,
    required bool napcatRunning,
    required String? napcatWebuiUrl,
  }) {
    final scheme = Theme.of(context).colorScheme;

    // 没有可选实例
    if (selected == null) {
      return _Placeholder(
        icon: _target.selectedIcon,
        title: '没有可用实例',
        message: _target == WebUiTarget.neoMofox
            ? '请先创建一个安装了 WebUI 的实例'
            : '请先创建一个安装了 NapCat 的实例',
        scheme: scheme,
      );
    }

    if (_target == WebUiTarget.neoMofox) {
      // Neo-MoFox WebUI
      if (!selected.installWebui) {
        return _Placeholder(
          icon: _target.selectedIcon,
          title: '此实例未安装 WebUI',
          message: '创建实例时勾选「安装 WebUI」即可使用',
          scheme: scheme,
        );
      }
      if (!botRunning) {
        _loadedForInstanceId = false;
        return _Placeholder(
          icon: _target.selectedIcon,
          title: 'Bot 未运行',
          message: '请先在实例详情页启动 Bot，再回来查看 WebUI',
          scheme: scheme,
        );
      }
      // 运行中 → 加载 WebUI（每个实例只加载一次，避免重复 load）
      if (!_loadedForInstanceId) {
        _loadedForInstanceId = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(webviewNotifierProvider.notifier).loadNeoMofox(selected);
        });
      }
      return WebViewWidget(controller: controller);
    }

    // NapCat WebUI
    if (!napcatRunning) {
      _loadedNapcatUrl = null;
      return _Placeholder(
        icon: _target.selectedIcon,
        title: 'NapCat 未运行',
        message: '请先在实例详情页启动 NapCat',
        scheme: scheme,
      );
    }
    if (napcatWebuiUrl == null || napcatWebuiUrl.isEmpty) {
      return _Placeholder(
        icon: _target.selectedIcon,
        title: '等待 NapCat WebUI 地址',
        message: 'NapCat 启动后会输出 WebUI 地址，请稍候…',
        scheme: scheme,
      );
    }
    // URL 变化时重新加载
    if (_loadedNapcatUrl != napcatWebuiUrl) {
      _loadedNapcatUrl = napcatWebuiUrl;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(webviewNotifierProvider.notifier).loadNapcat(napcatWebuiUrl);
      });
    }
    return WebViewWidget(controller: controller);
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.icon,
    required this.title,
    required this.message,
    required this.scheme,
  });

  final IconData icon;
  final String title;
  final String message;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 56, color: scheme.primary),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
