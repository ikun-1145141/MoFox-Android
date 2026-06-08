import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 体检结果。`null` = 检查中。
class SystemCheckResult {
  const SystemCheckResult({
    required this.label,
    required this.value,
    required this.passed,
  });
  final String label;
  final String value;
  final bool passed;
}

class SystemCheckState {
  const SystemCheckState({required this.items, required this.running});
  final List<SystemCheckResult> items;
  final bool running;

  bool get allPassed => items.every((r) => r.passed);
}

/// 占位实现：模拟一秒后给出结果。后端接通后改为读 `RuntimeBridge.probe()`。
final systemCheckProvider =
    NotifierProvider<SystemCheckNotifier, SystemCheckState>(
  SystemCheckNotifier.new,
);

class SystemCheckNotifier extends Notifier<SystemCheckState> {
  @override
  SystemCheckState build() {
    Future.microtask(run);
    return const SystemCheckState(items: [], running: true);
  }

  Future<void> run() async {
    state = const SystemCheckState(items: [], running: true);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    state = const SystemCheckState(
      running: false,
      items: <SystemCheckResult>[
        SystemCheckResult(
          label: 'CPU 架构',
          value: 'arm64-v8a',
          passed: true,
        ),
        SystemCheckResult(
          label: '剩余空间',
          value: '> 2 GB',
          passed: true,
        ),
        SystemCheckResult(
          label: '可用内存',
          value: '>= 1 GB',
          passed: true,
        ),
        SystemCheckResult(
          label: 'Android 版本',
          value: 'API 33+',
          passed: true,
        ),
      ],
    );
  }
}

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
          if (state.running)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            )
          else
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: <Widget>[
          Icon(
            item.passed ? Icons.check_circle : Icons.cancel,
            size: 20,
            color: item.passed ? scheme.primary : scheme.error,
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
