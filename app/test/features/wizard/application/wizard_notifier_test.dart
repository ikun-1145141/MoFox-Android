import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mofox_android/features/instance/domain/instance.dart';
import 'package:mofox_android/features/wizard/application/wizard_install_checkpoint_store.dart';
import 'package:mofox_android/features/wizard/application/wizard_notifier.dart';
import 'package:mofox_android/features/wizard/domain/wizard_step.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestDefaultBinaryMessenger messenger;
  late List<bool> keepScreenOnValues;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    keepScreenOnValues = <bool>[];
    messenger.setMockMethodCallHandler(
      const MethodChannel('mofox/platform'),
      (call) async {
        if (call.method == 'setKeepScreenOn') {
          final arguments = call.arguments! as Map<Object?, Object?>;
          keepScreenOnValues.add(arguments['enabled']! as bool);
        }
        return null;
      },
    );
    const codec = StandardMethodCodec();
    messenger.setMockMessageHandler('mofox/runtime/events', (message) async {
      codec.decodeMethodCall(message);
      return codec.encodeSuccessEnvelope(null);
    });
  });

  tearDown(() {
    messenger
      ..setMockMethodCallHandler(const MethodChannel('mofox/runtime'), null)
      ..setMockMethodCallHandler(const MethodChannel('mofox/platform'), null)
      ..setMockMessageHandler('mofox/runtime/events', null);
  });

  test('checkpoint serialization preserves the frozen draft and statuses', () {
    final checkpoint = WizardInstallCheckpoint(
      instanceId: 'instance-json',
      installDir: '/root/instances/instance-json',
      draft: _draft(apiKey: 'serialized-key').copyWith(
        webuiApiKey: 'serialized-web-key',
      ),
      taskStatus: <InstallTask, InstallTaskStatus>{
        for (final task in InstallTask.values)
          task: task == InstallTask.cloneRepo
              ? InstallTaskStatus.success
              : InstallTaskStatus.pending,
      },
    );

    final restored = WizardInstallCheckpoint.fromJson(checkpoint.toJson());

    expect(restored.instanceId, checkpoint.instanceId);
    expect(restored.draft.apiKey, 'serialized-key');
    expect(restored.draft.webuiApiKey, 'serialized-web-key');
    expect(
      restored.taskStatus[InstallTask.cloneRepo],
      InstallTaskStatus.success,
    );
  });

  test('resume without checkpoint clears keys from a later wizard', () async {
    final store = _MemoryCheckpointStore();
    final container = ProviderContainer(
      overrides: <Override>[
        wizardInstallCheckpointStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(wizardProvider.notifier)
      ..update(
        (draft) => draft.copyWith(
          apiKey: 'key-from-another-wizard',
          webuiApiKey: 'web-key-from-another-wizard',
        ),
      );

    await notifier.prepareResume(_failedInstance());

    final state = container.read(wizardProvider);
    expect(state.step, WizardStep.mirrorCheck);
    expect(state.draft.apiKey, isEmpty);
    expect(state.draft.webuiApiKey, isEmpty);
    expect(state.resumeAvailable, isFalse);
    expect(state.requiresReconfiguration, isTrue);
  });

  test('resume restores the encrypted checkpoint draft and completed tasks',
      () async {
    final checkpoint = WizardInstallCheckpoint(
      instanceId: 'instance-a',
      installDir: '/root/instances/instance-a',
      draft: _draft(apiKey: 'checkpoint-key'),
      taskStatus: <InstallTask, InstallTaskStatus>{
        for (final task in InstallTask.values)
          task: task == InstallTask.cloneRepo
              ? InstallTaskStatus.success
              : InstallTaskStatus.pending,
      },
    );
    final store = _MemoryCheckpointStore()
      ..records[checkpoint.instanceId] = checkpoint;
    final container = ProviderContainer(
      overrides: <Override>[
        wizardInstallCheckpointStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(wizardProvider.notifier)
        .prepareResume(_failedInstance());

    final state = container.read(wizardProvider);
    expect(state.step, WizardStep.install);
    expect(state.draft.apiKey, 'checkpoint-key');
    expect(state.taskStatus[InstallTask.cloneRepo], InstallTaskStatus.success);
    expect(state.resumeAvailable, isTrue);
  });

  test('running install freezes draft and rejects reset or concurrent start',
      () async {
    final enteredFirstTask = Completer<void>();
    final releaseFirstTask = Completer<void>();
    final runtimeArguments = <Map<Object?, Object?>>[];
    messenger.setMockMethodCallHandler(
      const MethodChannel('mofox/runtime'),
      (call) async {
        if (call.method != 'runInstallTask') return null;
        final envelope = call.arguments! as Map<Object?, Object?>;
        runtimeArguments.add(envelope['args']! as Map<Object?, Object?>);
        if (!enteredFirstTask.isCompleted) {
          enteredFirstTask.complete();
          await releaseFirstTask.future;
        }
        return <String, Object?>{
          'success': true,
          'logs': <String>[],
        };
      },
    );

    final store = _MemoryCheckpointStore();
    final container = ProviderContainer(
      overrides: <Override>[
        wizardInstallCheckpointStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(wizardProvider.notifier)
      ..update((_) => _draft(apiKey: 'frozen-key'));

    final install = notifier.startInstall();
    await enteredFirstTask.future;
    final runningId = container.read(wizardProvider).instanceId;
    expect(container.read(wizardProvider).installRunning, isTrue);
    expect(keepScreenOnValues, <bool>[true]);

    notifier
      ..resetForNewInstance()
      ..update((draft) => draft.copyWith(apiKey: 'mutated-key'));
    await notifier.startInstall();

    expect(container.read(wizardProvider).instanceId, runningId);
    expect(container.read(wizardProvider).draft.apiKey, 'frozen-key');
    expect(runtimeArguments, hasLength(1));

    releaseFirstTask.complete();
    await install;

    expect(container.read(wizardProvider).installFinished, isTrue);
    expect(container.read(wizardProvider).installRunning, isFalse);
    expect(
      runtimeArguments.map((args) => args['apiKey']),
      everyElement('frozen-key'),
    );
    expect(store.deletedIds, contains(runningId));
    expect(keepScreenOnValues, <bool>[true, false]);
  });

  test('failed secure checkpoint write never advertises resume', () async {
    final container = ProviderContainer(
      overrides: <Override>[
        wizardInstallCheckpointStoreProvider.overrideWithValue(
          _ThrowingCheckpointStore(),
        ),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(wizardProvider.notifier)
      ..update((_) => _draft(apiKey: 'secret'));

    await notifier.startInstall();

    final state = container.read(wizardProvider);
    expect(state.installRunning, isFalse);
    expect(state.installFinished, isFalse);
    expect(state.errorMessage, contains('secure storage unavailable'));
    expect(state.resumeAvailable, isFalse);
    expect(keepScreenOnValues, <bool>[true, false]);
  });
}

Instance _failedInstance() => Instance(
      id: 'instance-a',
      name: 'A',
      botQq: '10001',
      botNickname: 'bot',
      ownerQq: '10002',
      wsPort: 8095,
      channel: 'main',
      installNapcat: true,
      installWebui: false,
      installDir: '/root/instances/instance-a',
      createdAt: DateTime(2026),
      installStatus: InstanceInstallStatus.failed,
      lastInstallTask: InstallTask.cloneRepo.name,
      installError: 'failed',
    );

InstanceDraft _draft({required String apiKey}) => InstanceDraft(
      eulaAccepted: true,
      name: 'Frozen',
      botQq: '10001',
      botNickname: 'bot',
      ownerQq: '10002',
      apiKey: apiKey,
      installWebui: false,
    );

class _MemoryCheckpointStore implements WizardInstallCheckpointStore {
  final Map<String, WizardInstallCheckpoint> records =
      <String, WizardInstallCheckpoint>{};
  final List<String?> deletedIds = <String?>[];

  @override
  Future<void> delete(String instanceId) async {
    records.remove(instanceId);
    deletedIds.add(instanceId);
  }

  @override
  Future<WizardInstallCheckpoint?> read(String instanceId) async =>
      records[instanceId];

  @override
  Future<void> write(WizardInstallCheckpoint checkpoint) async {
    records[checkpoint.instanceId] = checkpoint;
  }
}

class _ThrowingCheckpointStore implements WizardInstallCheckpointStore {
  @override
  Future<void> delete(String instanceId) async {}

  @override
  Future<WizardInstallCheckpoint?> read(String instanceId) async => null;

  @override
  Future<void> write(WizardInstallCheckpoint checkpoint) async {
    throw StateError('secure storage unavailable');
  }
}
