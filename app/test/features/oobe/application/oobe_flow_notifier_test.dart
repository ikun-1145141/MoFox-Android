import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mofox_android/features/oobe/application/oobe_flow_notifier.dart';
import 'package:mofox_android/features/oobe/domain/oobe_step.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestDefaultBinaryMessenger messenger;
  late List<String> runtimeTasks;
  late List<bool> keepScreenOnValues;
  String? failingTask;

  setUp(() {
    messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    runtimeTasks = <String>[];
    keepScreenOnValues = <bool>[];
    failingTask = null;

    messenger.setMockMethodCallHandler(
      const MethodChannel('mofox/runtime'),
      (call) async {
        if (call.method != 'runInstallTask') return null;
        final arguments = call.arguments! as Map<Object?, Object?>;
        final task = arguments['task']! as String;
        runtimeTasks.add(task);
        if (task == failingTask) {
          return <String, Object?>{
            'success': false,
            'logs': <String>[],
            'error': '模拟安装失败',
          };
        }
        return <String, Object?>{
          'success': true,
          'logs': <String>[],
        };
      },
    );
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

  test('default flow skips NapCat and still completes', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(oobeFlowProvider.notifier);

    expect(container.read(oobeFlowProvider).installNapcat, isFalse);

    await notifier.runRuntimeInstall();

    final state = container.read(oobeFlowProvider);
    expect(runtimeTasks, <String>['extractRootfs', 'installRuntimeDeps']);
    expect(state.result, isA<OobeStepSuccess>());
    expect(state.logs.join('\n'), contains('未安装 NapCat'));
    expect(keepScreenOnValues, <bool>[true, false]);
  });

  test('opt-in flow installs and verifies NapCat', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(oobeFlowProvider.notifier)
      ..setInstallNapcat(true);

    await notifier.runRuntimeInstall();

    expect(
      runtimeTasks,
      <String>[
        'extractRootfs',
        'installRuntimeDeps',
        'installNapcat',
        'verifyNapcat',
      ],
    );
    expect(container.read(oobeFlowProvider).result, isA<OobeStepSuccess>());
  });

  test('failed runtime install always releases the wake lock', () async {
    failingTask = 'installRuntimeDeps';
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(oobeFlowProvider.notifier).runRuntimeInstall();

    expect(container.read(oobeFlowProvider).result, isA<OobeStepFailure>());
    expect(keepScreenOnValues, <bool>[true, false]);
  });
}
