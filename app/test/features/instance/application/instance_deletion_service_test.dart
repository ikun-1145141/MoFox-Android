import 'package:flutter_test/flutter_test.dart';
import 'package:mofox_android/features/instance/application/instance_deletion_service.dart';
import 'package:mofox_android/features/instance/domain/instance.dart';

void main() {
  test('active instance is stopped before directory, key, and record cleanup',
      () async {
    final calls = <String>[];
    final service = InstanceDeletionService(
      deleteDirectory: (_) async => calls.add('directory'),
      deleteWebuiKey: (_) async => calls.add('key'),
      removeRecord: (_) async => calls.add('record'),
    );

    await service.delete(
      _instance,
      isActive: true,
      stopActiveProcesses: () async => calls.add('stop'),
    );

    expect(calls, <String>['stop', 'directory', 'key', 'record']);
  });

  test('remote cleanup failure preserves key and local record', () async {
    final calls = <String>[];
    final service = InstanceDeletionService(
      deleteDirectory: (_) async {
        calls.add('directory');
        throw StateError('remote failed');
      },
      deleteWebuiKey: (_) async => calls.add('key'),
      removeRecord: (_) async => calls.add('record'),
    );

    await expectLater(
      service.delete(
        _instance,
        isActive: false,
        stopActiveProcesses: () async => calls.add('stop'),
      ),
      throwsA(
        isA<InstanceDeletionException>().having(
          (error) => error.stage,
          'stage',
          InstanceDeletionStage.deletingDirectory,
        ),
      ),
    );
    expect(calls, <String>['directory']);
  });

  test('active process stop failure prevents every destructive step', () async {
    final calls = <String>[];
    final service = InstanceDeletionService(
      deleteDirectory: (_) async => calls.add('directory'),
      deleteWebuiKey: (_) async => calls.add('key'),
      removeRecord: (_) async => calls.add('record'),
    );

    await expectLater(
      service.delete(
        _instance,
        isActive: true,
        stopActiveProcesses: () async {
          calls.add('stop');
          throw StateError('stop failed');
        },
      ),
      throwsA(
        isA<InstanceDeletionException>().having(
          (error) => error.stage,
          'stage',
          InstanceDeletionStage.stoppingProcesses,
        ),
      ),
    );
    expect(calls, <String>['stop']);
  });

  test('key cleanup failure keeps the retryable local record', () async {
    final calls = <String>[];
    final service = InstanceDeletionService(
      deleteDirectory: (_) async => calls.add('directory'),
      deleteWebuiKey: (_) async {
        calls.add('key');
        throw StateError('keystore failed');
      },
      removeRecord: (_) async => calls.add('record'),
    );

    await expectLater(
      service.delete(
        _instance,
        isActive: false,
        stopActiveProcesses: () async => calls.add('stop'),
      ),
      throwsA(
        isA<InstanceDeletionException>().having(
          (error) => error.stage,
          'stage',
          InstanceDeletionStage.deletingSecret,
        ),
      ),
    );
    expect(calls, <String>['directory', 'key']);
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
  installWebui: true,
  installDir: '/root/instances/test-instance',
  createdAt: DateTime.utc(2026),
);
