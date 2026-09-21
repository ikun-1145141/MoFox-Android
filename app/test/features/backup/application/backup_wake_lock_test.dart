import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mofox_android/core/platform/screen_wake_lock.dart';
import 'package:mofox_android/features/backup/application/backup_service.dart';
import 'package:mofox_android/features/instance/domain/instance.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestDefaultBinaryMessenger messenger;
  late List<bool> keepScreenOnValues;

  setUp(() {
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
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(
      const MethodChannel('mofox/platform'),
      null,
    );
  });

  test('backup export keeps the screen awake until packaging finishes',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final service = _BlockingBackupService();
    final notifier = BackupNotifier(
      service,
      container.read(screenWakeLockProvider),
    );
    addTearDown(notifier.dispose);

    final export = notifier.exportFullBackup(instance: _instance);
    await service.started.future;

    expect(notifier.state.isExporting, isTrue);
    expect(keepScreenOnValues, <bool>[true]);

    service.finish.complete();
    await export;

    expect(notifier.state.isExporting, isFalse);
    expect(keepScreenOnValues, <bool>[true, false]);
  });
}

class _BlockingBackupService implements BackupService {
  final Completer<void> started = Completer<void>();
  final Completer<void> finish = Completer<void>();

  @override
  Future<String?> exportFullBackup({
    required Instance instance,
    bool includeLogs = true,
    int logDays = 7,
  }) async {
    started.complete();
    await finish.future;
    return 'content://backup';
  }

  @override
  Future<String?> exportSingle({
    required String rootfsPath,
    required String exportName,
  }) async =>
      'content://backup';

  @override
  Future<int> importBackup({required Instance instance}) async => 1;
}

final Instance _instance = Instance(
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
  createdAt: DateTime.utc(2026),
);
