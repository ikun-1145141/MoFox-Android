import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mofox_android/features/instance/application/instance_repository.dart';
import 'package:mofox_android/features/instance/domain/instance.dart';
import 'package:mofox_android/features/wizard/application/wizard_install_checkpoint_store.dart';
import 'package:mofox_android/features/wizard/application/wizard_notifier.dart';
import 'package:mofox_android/features/wizard/presentation/widgets/account_step.dart';
import 'package:mofox_android/features/wizard/presentation/widgets/instance_info_step.dart';
import 'package:mofox_android/features/wizard/presentation/widgets/model_step.dart';
import 'package:mofox_android/features/wizard/presentation/widgets/network_step.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const launcherChannel = MethodChannel('plugins.flutter.io/url_launcher');
  late TestDefaultBinaryMessenger messenger;

  setUp(() {
    messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      launcherChannel,
      (_) async => false,
    );
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(launcherChannel, null);
  });

  testWidgets('form fields show validation errors and enforce input lengths',
      (tester) async {
    final container = ProviderContainer(
      overrides: <Override>[
        instancesProvider.overrideWith(
          (_) async => <Instance>[_instance('other', 'Existing')],
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(wizardProvider.notifier).update(
          (draft) => draft.copyWith(
            name: 'existing',
            botQq: '1234',
            ownerQq: '1234567890123',
            apiKey: 'too-short',
            wsPort: 65536,
            installWebui: true,
            webuiApiKey: 'short',
          ),
        );

    await _pumpStep(tester, container, const InstanceInfoStep());
    expect(find.text('已有同名实例'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey<String>('wizard-instance-name')),
      'a' * 40,
    );
    await tester.pump();
    expect(container.read(wizardProvider).draft.name, hasLength(32));

    await _pumpStep(tester, container, const AccountStep());
    expect(find.text('Bot QQ应为 5–12 位数字'), findsOneWidget);
    expect(find.text('主人 QQ应为 5–12 位数字'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey<String>('wizard-bot-qq')),
      '1234567890123',
    );
    await tester.pump();
    expect(container.read(wizardProvider).draft.botQq, '123456789012');

    await _pumpStep(tester, container, const ModelStep());
    expect(find.text('API Key 格式过短，请检查是否完整'), findsOneWidget);
    expect(find.byTooltip('显示 API Key'), findsOneWidget);
    await tester.tap(find.byTooltip('显示 API Key'));
    await tester.pump();
    expect(find.byTooltip('隐藏 API Key'), findsOneWidget);

    await tester.tap(find.text('获取密钥'));
    await tester.pump();
    expect(find.text('无法打开密钥获取页面，请稍后重试。'), findsOneWidget);

    await _pumpStep(tester, container, const NetworkStep());
    expect(find.text('端口必须在 1–65535 之间'), findsOneWidget);
    expect(find.text('建议使用至少 12 位的 WebUI 密钥'), findsOneWidget);
  });

  testWidgets('resume name validation excludes the current instance',
      (tester) async {
    final current = _instance('current', 'My Bot');
    final container = ProviderContainer(
      overrides: <Override>[
        instancesProvider.overrideWith((_) async => <Instance>[current]),
        wizardInstallCheckpointStoreProvider.overrideWithValue(
          const _NullCheckpointStore(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(wizardProvider.notifier).prepareResume(current);
    await _pumpStep(tester, container, const InstanceInfoStep());

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration?.errorText, isNull);
    expect(find.text('已有同名实例'), findsNothing);
  });
}

Future<void> _pumpStep(
  WidgetTester tester,
  ProviderContainer container,
  Widget step,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: Scaffold(body: step)),
    ),
  );
  await tester.pumpAndSettle();
}

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
      installStatus: InstanceInstallStatus.failed,
    );

class _NullCheckpointStore implements WizardInstallCheckpointStore {
  const _NullCheckpointStore();

  @override
  Future<void> delete(String instanceId) async {}

  @override
  Future<WizardInstallCheckpoint?> read(String instanceId) async => null;

  @override
  Future<void> write(WizardInstallCheckpoint checkpoint) async {}
}
