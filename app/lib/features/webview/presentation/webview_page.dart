import 'package:flutter/material.dart';

enum WebUiTarget { neoMofox, napcat }

extension on WebUiTarget {
  String get label => switch (this) {
        WebUiTarget.neoMofox => 'Neo-MoFox',
        WebUiTarget.napcat => 'Napcat',
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

class WebViewPage extends StatefulWidget {
  const WebViewPage({super.key});
  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  WebUiTarget _target = WebUiTarget.neoMofox;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('管理'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            onPressed: () {},
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: '在浏览器打开',
            onPressed: () {},
            icon: const Icon(Icons.open_in_new),
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SegmentedButton<WebUiTarget>(
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
              onSelectionChanged: (s) => setState(() => _target = s.first),
            ),
          ),
        ),
      ),
      body: ColoredBox(
        color: scheme.surface,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  _target.selectedIcon,
                  size: 56,
                  color: scheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  '${_target.label} 控制台',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  _target == WebUiTarget.neoMofox
                      ? '启动 Bot 后这里会加载 http://127.0.0.1:8000/webui/'
                      : '启动 Napcat 后这里会加载本地 Napcat 控制台',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
