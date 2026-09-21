import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mofox_android/features/dashboard/application/process_console_provider.dart';
import 'package:mofox_android/features/instance/domain/instance.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestDefaultBinaryMessenger messenger;
  late List<String> actions;
  late List<bool> keepScreenOnValues;
  late Map<String, String> processStatus;
  var failNapcatInstall = false;

  setUp(() {
    messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    actions = <String>[];
    keepScreenOnValues = <bool>[];
    processStatus = <String, String>{
      'bot': 'stopped',
      'napcat': 'stopped',
      'activeInstanceId': '',
    };
    failNapcatInstall = false;

    messenger.setMockMethodCallHandler(
      const MethodChannel('mofox/runtime'),
      (call) async {
        switch (call.method) {
          case 'processStatus':
            return Map<String, String>.of(processStatus);
          case 'runInstallTask':
            final arguments = call.arguments! as Map<Object?, Object?>;
            final task = arguments['task']! as String;
            actions.add(task);
            if (failNapcatInstall && task == 'installNapcat') {
              return <String, Object?>{
                'success': false,
                'logs': <String>[],
                'error': '下载失败',
              };
            }
            return <String, Object?>{
              'success': true,
              'logs': <String>[],
            };
          case 'startProcess':
            final arguments = call.arguments! as Map<Object?, Object?>;
            final name = arguments['name']! as String;
            final args = arguments['args']! as Map<Object?, Object?>;
            actions.add('start:$name');
            processStatus[name] = 'running';
            processStatus['activeInstanceId'] =
                args['instanceId']?.toString() ?? '';
            return null;
          case 'stopProcess':
            final arguments = call.arguments! as Map<Object?, Object?>;
            final name = arguments['name']! as String;
            actions.add('stop:$name');
            processStatus[name] = 'stopped';
            if (processStatus['bot'] == 'stopped' &&
                processStatus['napcat'] == 'stopped') {
              processStatus['activeInstanceId'] = '';
            }
            return null;
          case 'restartProcess':
            final arguments = call.arguments! as Map<Object?, Object?>;
            final name = arguments['name']! as String;
            final args = arguments['args']! as Map<Object?, Object?>;
            actions.add('restart:$name');
            processStatus[name] = 'running';
            processStatus['activeInstanceId'] =
                args['instanceId']?.toString() ?? '';
            return null;
        }
        return null;
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

  test('first NapCat start lazily installs, verifies, then starts', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(processConsoleProvider.notifier);

    await notifier.startNapcat(_instance);

    expect(
      actions,
      <String>['installNapcat', 'verifyNapcat', 'start:napcat'],
    );
    expect(container.read(processConsoleProvider).errorMessage, isNull);
    expect(keepScreenOnValues, <bool>[true, false]);
  });

  test('NapCat install failure prevents process start', () async {
    failNapcatInstall = true;
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(processConsoleProvider.notifier);

    await notifier.startNapcat(_instance);

    expect(actions, <String>['installNapcat']);
    expect(
      container.read(processConsoleProvider).errorMessage,
      contains('下载失败'),
    );
    expect(keepScreenOnValues, <bool>[true, false]);
  });

  test('only the active instance reports the global bot as running', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(processConsoleProvider.notifier);
    await notifier.refreshStatus();

    await notifier.startBot(_instance);

    final state = container.read(processConsoleProvider);
    expect(state.activeInstanceId, _instance.id);
    expect(state.botStatusFor(_instance.id), 'running');
    expect(state.botStatusFor('another-instance'), 'stopped');
  });

  test('starting a second instance does not steal the active process',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(processConsoleProvider.notifier);
    await notifier.refreshStatus();
    await notifier.startBot(_instance);
    actions.clear();

    await notifier.startBot(_otherInstance);

    final state = container.read(processConsoleProvider);
    expect(actions, isEmpty);
    expect(state.activeInstanceId, _instance.id);
    expect(state.botStatusFor(_otherInstance.id), 'stopped');
    expect(state.errorMessage, contains('另一个实例'));
  });

  test('a running process with unknown ownership cannot be claimed', () async {
    processStatus['bot'] = 'running';
    processStatus['activeInstanceId'] = '';
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(processConsoleProvider.notifier);
    await notifier.refreshStatus();
    actions.clear();

    await notifier.startBot(_instance);

    expect(actions, isEmpty);
    expect(
      container.read(processConsoleProvider).errorMessage,
      contains('身份未知'),
    );
  });

  test('stopping all active processes clears the active instance', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(processConsoleProvider.notifier);
    await notifier.refreshStatus();
    await notifier.startBot(_instance);

    await notifier.stopActiveInstance(_instance.id);

    final state = container.read(processConsoleProvider);
    expect(actions, contains('stop:bot'));
    expect(state.activeInstanceId, isNull);
    expect(state.botStatus, 'stopped');
    expect(state.napcatStatus, 'stopped');
  });
}

final Instance _instance = Instance(
  id: 'test-instance',
  name: '测试实例',
  botQq: '123456',
  botNickname: 'Bot',
  ownerQq: '654321',
  wsPort: 8095,
  channel: 'main',
  installNapcat: true,
  installWebui: false,
  installDir: '/root/instances/test-instance',
  createdAt: DateTime.utc(2026),
);

final Instance _otherInstance = Instance(
  id: 'other-instance',
  name: '另一个实例',
  botQq: '223456',
  botNickname: 'Other',
  ownerQq: '654321',
  wsPort: 8096,
  channel: 'main',
  installNapcat: true,
  installWebui: false,
  installDir: '/root/instances/other-instance',
  createdAt: DateTime.utc(2026),
);
