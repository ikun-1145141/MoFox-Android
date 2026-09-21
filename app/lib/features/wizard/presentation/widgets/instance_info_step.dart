import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/wizard_notifier.dart';
import '../../domain/wizard_validation.dart';

class InstanceInfoStep extends ConsumerWidget {
  const InstanceInfoStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(wizardProvider).draft;
    final notifier = ref.read(wizardProvider.notifier);
    final existingNames = ref.watch(wizardExistingInstanceNamesProvider);
    final localError = WizardValidation.instanceName(draft.name);
    final nameError = localError ??
        existingNames.when(
          data: (names) => WizardValidation.instanceName(
            draft.name,
            existingNames: names,
          ),
          error: (_, __) => '无法读取已有实例，暂时不能继续',
          loading: () => null,
        );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextFormField(
            key: const ValueKey<String>('wizard-instance-name'),
            initialValue: draft.name,
            maxLength: 32,
            inputFormatters: <TextInputFormatter>[
              LengthLimitingTextInputFormatter(32),
            ],
            decoration: InputDecoration(
              labelText: '实例名称',
              hintText: '例如：我的墨狐',
              prefixIcon: const Icon(Icons.badge_outlined),
              border: const OutlineInputBorder(),
              errorText: nameError,
              helperText: existingNames.isLoading ? '正在检查是否与已有实例重名…' : null,
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
