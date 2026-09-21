import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mofox_android/features/instance/application/instance_repository.dart';
import 'package:mofox_android/features/instance/domain/instance.dart';
import 'package:mofox_android/features/wizard/application/wizard_network_checks.dart';
import 'package:mofox_android/features/wizard/application/wizard_notifier.dart';
import 'package:mofox_android/features/wizard/domain/wizard_step.dart';
import 'package:mofox_android/features/wizard/presentation/wizard_page.dart';

void main() {
  testWidgets('failed EULA cannot be accepted and keeps next disabled',
      (tester) async {
    final container = ProviderContainer(
      overrides: <Override>[
        mirrorProbeProvider.overrideWithValue(
          (source) async => MirrorProbeResult(
            mirror: source,
            reachable: true,
            latencyMs: source.id == 'github' ? 1 : 10,
          ),
        ),
        eulaLoaderProvider.overrideWithValue(
          (source) async => throw StateError('offline'),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: WizardPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.text('EULA 获取失败'), findsOneWidget);

    container.read(wizardProvider.notifier).update(
          (draft) => draft.copyWith(eulaAccepted: true),
        );
    await tester.pump();

    final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
    expect(checkbox.value, isFalse);
    expect(checkbox.onChanged, isNull);
    final next = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '下一步'),
    );
    expect(next.onPressed, isNull);
  });

  testWidgets('every form gate and summary use complete validation',
      (tester) async {
    final container = ProviderContainer(
      overrides: <Override>[
        instancesProvider.overrideWith(
          (_) async => <Instance>[_instance('existing', 'Existing')],
        ),
        mirrorProbeProvider.overrideWithValue(
          (source) async => MirrorProbeResult(
            mirror: source,
            reachable: true,
            latencyMs: 1,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: WizardPage()),
      ),
    );
    await tester.pumpAndSettle();

    final notifier = container.read(wizardProvider.notifier);
    notifier
      ..update((_) => _validDraft().copyWith(name: 'existing'))
      ..goTo(WizardStep.instanceInfo);
    await tester.pumpAndSettle();
    expect(_primaryButton(tester).onPressed, isNull);

    notifier
      ..update((draft) => draft.copyWith(name: 'Unique', botQq: '1234'))
      ..goTo(WizardStep.account);
    await tester.pumpAndSettle();
    expect(_primaryButton(tester).onPressed, isNull);

    notifier
      ..update(
        (draft) => draft.copyWith(
          botQq: '123456789',
          apiKey: 'short',
        ),
      )
      ..goTo(WizardStep.model);
    await tester.pumpAndSettle();
    expect(_primaryButton(tester).onPressed, isNull);

    notifier
      ..update(
        (draft) => draft.copyWith(
          apiKey: 'sk-1234567890123456',
          wsPort: 65536,
        ),
      )
      ..goTo(WizardStep.network);
    await tester.pumpAndSettle();
    expect(_primaryButton(tester).onPressed, isNull);

    notifier
      ..update((draft) => draft.copyWith(wsPort: 8095))
      ..goTo(WizardStep.summary);
    await tester.pumpAndSettle();
    expect(_primaryButton(tester).onPressed, isNotNull);

    notifier.update((draft) => draft.copyWith(ownerQq: '12'));
    await tester.pump();
    expect(_primaryButton(tester).onPressed, isNull);
  });
}

FilledButton _primaryButton(WidgetTester tester) {
  final next = find.widgetWithText(FilledButton, '下一步');
  final finder = next.evaluate().isNotEmpty
      ? next
      : find.widgetWithText(FilledButton, '开始安装');
  return tester.widget<FilledButton>(finder);
}

InstanceDraft _validDraft() => const InstanceDraft(
      eulaAccepted: true,
      name: 'Unique',
      botQq: '123456789',
      botNickname: 'Bot',
      ownerQq: '987654321',
      apiKey: 'sk-1234567890123456',
      wsPort: 8095,
      channel: 'main',
      webuiApiKey: 'long-random-secret',
      installWebui: true,
    );

Instance _instance(String id, String name) => Instance(
      id: id,
      name: name,
      botQq: '123456789',
      botNickname: 'Bot',
      ownerQq: '987654321',
      wsPort: 8095,
      channel: 'main',
      installNapcat: true,
      installWebui: true,
      installDir: '/root/instances/$id',
      createdAt: DateTime.utc(2026),
    );
