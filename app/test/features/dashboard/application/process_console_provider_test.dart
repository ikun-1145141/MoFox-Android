import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mofox_android/features/dashboard/application/process_console_provider.dart';
import 'package:mofox_android/features/instance/domain/instance.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const codec = StandardMethodCodec();

  late TestDefaultBinaryMessenger messenger;
  late List<String> actions;
  late List<bool> keepScreenOnValues;
  late Map<String, String> processStatus;
  var failSnowlumaInstall = false;

  void emitProcessEvent(String name, String line) {
    messenger.handlePlatformMessage(
      'mofox/runtime/events',
      codec.encodeSuccessEnvelope(<String, Object?>{
        'topic': 'process',
        'payload': <String, Object?>{'name': name, 'line': line},
      }),
      (_) {},
    );
  }

  setUp(() {
    messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    actions = <String>[];
    keepScreenOnValues = <bool>[];
    processStatus = <String, String>{
      'bot': 'stopped',
      'snowluma': 'stopped',
      'activeInstanceId': '',
    };
    failSnowlumaInstall = false;

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
            if (failSnowlumaInstall && task == 'installSnowluma') {
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
                processStatus['snowluma'] == 'stopped') {
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

  test('first SnowLuma start lazily installs, verifies, then starts', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(processConsoleProvider.notifier);

    await notifier.startSnowluma(_instance);

    expect(
      actions,
      <String>['installSnowluma', 'verifySnowluma', 'start:snowluma'],
    );
    expect(container.read(processConsoleProvider).errorMessage, isNull);
    expect(keepScreenOnValues, <bool>[true, false]);
  });

  test('SnowLuma install failure prevents process start', () async {
    failSnowlumaInstall = true;
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(processConsoleProvider.notifier);

    await notifier.startSnowluma(_instance);

    expect(actions, <String>['installSnowluma']);
    expect(
      container.read(processConsoleProvider).errorMessage,
      contains('下载失败'),
    );
    expect(keepScreenOnValues, <bool>[true, false]);
  });

  test('cancelSnowlumaLogin stops the snowluma process', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(processConsoleProvider.notifier);
    await notifier.startSnowluma(_instance);
    actions.clear();

    await notifier.cancelSnowlumaLogin();

    expect(actions, <String>['stop:snowluma']);
    expect(container.read(processConsoleProvider).snowlumaStatus, 'stopped');
    expect(container.read(processConsoleProvider).activeInstanceId, isNull);
  });

  test('QR payload from process stream is cleared by MOFOX_LOGIN_OK', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(processConsoleProvider.notifier);
    await notifier.startSnowluma(_instance);

    emitProcessEvent(
      'snowluma',
      'MOFOX_QR_IMAGE=/root/snowluma/cache/screen.png',
    );
    await pumpEventQueue();
    final payload =
        container.read(processConsoleProvider).snowlumaQrPayload;
    expect(payload, isNotNull);
    expect(payload, startsWith('file:/root/snowluma/cache/screen.png#'));

    emitProcessEvent('snowluma', 'MOFOX_LOGIN_OK=1');
    await pumpEventQueue();
    expect(
      container.read(processConsoleProvider).snowlumaQrPayload,
      isNull,
    );
  });

  test('legacy 配置加载 log line also clears the QR payload', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(processConsoleProvider.notifier);
    await notifier.startSnowluma(_instance);

    emitProcessEvent(
      'snowluma',
      'MOFOX_QR_IMAGE=/root/snowluma/cache/screen.png',
    );
    await pumpEventQueue();
    expect(
      container.read(processConsoleProvider).snowlumaQrPayload,
      isNotNull,
    );

    emitProcessEvent('snowluma', '[info] 配置加载完成');
    await pumpEventQueue();
    expect(
      container.read(processConsoleProvider).snowlumaQrPayload,
      isNull,
    );
  });

  test('MOFOX_WEBUI_URL from process stream updates snowlumaWebuiUrl',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(processConsoleProvider.notifier);
    await notifier.startSnowluma(_instance);
    expect(container.read(processConsoleProvider).snowlumaWebuiUrl, isNull);

    emitProcessEvent(
      'snowluma',
      'MOFOX_WEBUI_URL=http://127.0.0.1:5099/?token=x',
    );
    await pumpEventQueue();

    expect(
      container.read(processConsoleProvider).snowlumaWebuiUrl,
      'http://127.0.0.1:5099/?token=x',
    );
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
    expect(state.snowlumaStatus, 'stopped');
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
  installSnowluma: true,
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
  installSnowluma: true,
  installWebui: false,
  installDir: '/root/instances/other-instance',
  createdAt: DateTime.utc(2026),
);
