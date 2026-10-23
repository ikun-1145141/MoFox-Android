import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mofox_android/features/settings/application/snowluma_maintenance_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const codec = StandardMethodCodec();

  late TestDefaultBinaryMessenger messenger;
  late List<String> actions;
  var verifyLogs = <String>[];
  var failInstall = false;

  setUp(() {
    messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    actions = <String>[];
    verifyLogs = <String>[];
    failInstall = false;

    messenger.setMockMethodCallHandler(
      const MethodChannel('mofox/runtime'),
      (call) async {
        switch (call.method) {
          case 'runInstallTask':
            final arguments = call.arguments! as Map<Object?, Object?>;
            final task = arguments['task']! as String;
            actions.add(task);
            if (failInstall && task == 'installSnowluma') {
              return <String, Object?>{
                'success': false,
                'logs': <String>[],
                'error': '下载失败',
              };
            }
            return <String, Object?>{
              'success': true,
              'logs': task == 'verifySnowluma' ? verifyLogs : <String>[],
            };
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
    messenger.setMockMethodCallHandler(
      const MethodChannel('mofox/runtime'),
      null,
    );
    messenger.setMockMessageHandler('mofox/runtime/events', null);
  });

  test('checkAndRepair runs install then verify and parses version', () async {
    verifyLogs = <String>['MOFOX_SL_VERSION=v2.1.1'];
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(snowlumaMaintenanceProvider.notifier);

    final success = await notifier.checkAndRepair();

    expect(success, isTrue);
    expect(actions, <String>['installSnowluma', 'verifySnowluma']);
    final state = container.read(snowlumaMaintenanceProvider);
    expect(state.running, isFalse);
    expect(state.installedVersion, 'v2.1.1');
    expect(state.lastResultMessage, contains('重启 SnowLuma 后才能生效'));
  });

  test('checkAndRepair failure stops before verify and reports', () async {
    failInstall = true;
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(snowlumaMaintenanceProvider.notifier);

    final success = await notifier.checkAndRepair();

    expect(success, isFalse);
    expect(actions, <String>['installSnowluma']);
    final state = container.read(snowlumaMaintenanceProvider);
    expect(state.lastResultMessage, contains('修复失败'));
    expect(state.running, isFalse);
  });

  test('checkAndRepair is reentrant-guarded while running', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(snowlumaMaintenanceProvider.notifier);

    // 第一个调用尚未完成时，第二次调用应直接返回 false 而不追加任务。
    final first = notifier.checkAndRepair();
    final second = await notifier.checkAndRepair();
    await first;

    expect(second, isFalse);
    expect(actions, <String>['installSnowluma', 'verifySnowluma']);
  });
}
