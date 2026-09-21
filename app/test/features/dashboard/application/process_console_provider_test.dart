import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mofox_android/features/dashboard/application/process_console_provider.dart';
import 'package:mofox_android/features/instance/domain/instance.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestDefaultBinaryMessenger messenger;
  late List<String> actions;
  var failNapcatInstall = false;

  setUp(() {
    messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    actions = <String>[];
    failNapcatInstall = false;

    messenger.setMockMethodCallHandler(
      const MethodChannel('mofox/runtime'),
      (call) async {
        switch (call.method) {
          case 'processStatus':
            return <String, String>{
              'bot': 'stopped',
              'napcat': 'stopped',
            };
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
            actions.add('start:${arguments['name']}');
            return null;
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
