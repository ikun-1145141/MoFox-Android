import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/system_check_provider.dart';

/// OOBE 第 2 步：系统体检。
class SystemCheckStep extends ConsumerWidget {
  const SystemCheckStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final state = ref.watch(systemCheckProvider);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.health_and_safety_outlined,
              size: 44,
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '系统体检',
            style: text.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '检查设备是否满足运行要求。',
            style: text.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: <Widget>[
                for (var i = 0; i < state.items.length; i++) ...<Widget>[
                  if (i > 0) Divider(height: 1, color: scheme.outlineVariant),
                  _CheckTile(item: state.items[i]),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (!state.running && state.allPassed)
            Row(
              children: <Widget>[
                Icon(
                  Icons.verified_outlined,
                  size: 18,
                  color: scheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '体检通过，可以继续。',
                  style: text.bodyMedium?.copyWith(color: scheme.primary),
                ),
              ],
            ),
          if (!state.running && !state.allPassed) ...<Widget>[
            Text(
              state.hasUnknown
                  ? '部分项目未检测，必须重试并全部通过后才能继续。'
                  : '设备未满足运行要求，暂时无法继续。',
              style: text.bodyMedium?.copyWith(color: scheme.error),
            ),
            if (state.errorMessage != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                state.errorMessage!,
                style: text.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => ref.read(systemCheckProvider.notifier).run(),
                icon: const Icon(Icons.refresh),
                label: const Text('重新检测'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CheckTile extends StatelessWidget {
  const _CheckTile({required this.item});
  final SystemCheckResult item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final (icon, color) = switch (item.status) {
      SystemCheckStatus.checking => (Icons.pending_outlined, scheme.outline),
      SystemCheckStatus.passed => (Icons.check_circle, scheme.primary),
      SystemCheckStatus.failed => (Icons.cancel, scheme.error),
      SystemCheckStatus.unknown => (Icons.help_outline, scheme.error),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: <Widget>[
          Icon(
            icon,
            size: 20,
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              item.label,
              style: text.bodyLarge?.copyWith(color: scheme.onSurface),
            ),
          ),
          Text(
            item.value,
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
