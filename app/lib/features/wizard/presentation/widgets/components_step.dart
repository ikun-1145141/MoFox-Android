import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/wizard_notifier.dart';

class ComponentsStep extends ConsumerWidget {
  const ComponentsStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(wizardProvider).draft;
    final notifier = ref.read(wizardProvider.notifier);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: <Widget>[
        _ComponentTile(
          icon: Icons.qr_code_2_outlined,
          title: 'NapCat 适配器',
          subtitle: '提供 OneBot v11 协议接入，扫码登录 QQ',
          recommended: true,
          value: draft.installNapcat,
          onChanged: (v) =>
              notifier.update((d) => d.copyWith(installNapcat: v)),
        ),
        const SizedBox(height: 12),
        _ComponentTile(
          icon: Icons.web_outlined,
          title: 'WebUI 管理面板',
          subtitle: '在浏览器中可视化管理你的 Bot',
          recommended: true,
          value: draft.installWebui,
          onChanged: (v) =>
              notifier.update((d) => d.copyWith(installWebui: v)),
        ),
      ],
    );
  }
}

class _ComponentTile extends StatelessWidget {
  const _ComponentTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.recommended = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool recommended;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            title,
                            style: text.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                        if (recommended) ...<Widget>[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.tertiaryContainer,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '推荐',
                              style: text.labelSmall?.copyWith(
                                color: scheme.onTertiaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}
