import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/wizard_notifier.dart';

class InstanceInfoStep extends ConsumerWidget {
  const InstanceInfoStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(wizardProvider).draft;
    final notifier = ref.read(wizardProvider.notifier);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextFormField(
            initialValue: draft.name,
            decoration: const InputDecoration(
              labelText: '实例名称',
              hintText: '例如：我的墨狐',
              prefixIcon: Icon(Icons.badge_outlined),
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => notifier.update((d) => d.copyWith(name: v)),
          ),
          const SizedBox(height: 12),
          Text(
            '同一台设备上可以创建多个实例，名称用于区分。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}
