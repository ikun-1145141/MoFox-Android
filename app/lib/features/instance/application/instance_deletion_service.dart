import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mofox_android/core/runtime/runtime_bridge.dart';
import 'package:mofox_android/core/security/webui_key_store.dart';
import 'package:mofox_android/features/instance/application/instance_repository.dart';
import 'package:mofox_android/features/instance/domain/instance.dart';

typedef InstanceDeletionStep = Future<void> Function();
typedef InstanceDirectoryDeleter = Future<void> Function(Instance instance);
typedef InstanceIdDeleter = Future<void> Function(String instanceId);

/// 按可恢复顺序删除实例。
///
/// 本地记录最后移除。此前任一步失败时，实例仍会留在列表中，用户可以看到错误并
/// 重试；远端目录删除是幂等操作，因此密钥清理或记录写入失败后也可以安全重试。
class InstanceDeletionService {
  const InstanceDeletionService({
    required InstanceDirectoryDeleter deleteDirectory,
    required InstanceIdDeleter deleteWebuiKey,
    required InstanceIdDeleter removeRecord,
  })  : _deleteDirectory = deleteDirectory,
        _deleteWebuiKey = deleteWebuiKey,
        _removeRecord = removeRecord;

  final InstanceDirectoryDeleter _deleteDirectory;
  final InstanceIdDeleter _deleteWebuiKey;
  final InstanceIdDeleter _removeRecord;

  Future<void> delete(
    Instance instance, {
    required bool isActive,
    required InstanceDeletionStep stopActiveProcesses,
  }) async {
    if (isActive) {
      await _runStep(
        InstanceDeletionStage.stoppingProcesses,
        stopActiveProcesses,
      );
    }
    await _runStep(
      InstanceDeletionStage.deletingDirectory,
      () => _deleteDirectory(instance),
    );
    await _runStep(
      InstanceDeletionStage.deletingSecret,
      () => _deleteWebuiKey(instance.id),
    );
    await _runStep(
      InstanceDeletionStage.removingRecord,
      () => _removeRecord(instance.id),
    );
  }

  Future<void> _runStep(
    InstanceDeletionStage stage,
    InstanceDeletionStep action,
  ) async {
    try {
      await action();
    } on InstanceDeletionException {
      rethrow;
    } catch (error) {
      throw InstanceDeletionException(stage, error);
    }
  }
}

enum InstanceDeletionStage {
  stoppingProcesses,
  deletingDirectory,
  deletingSecret,
  removingRecord,
}

class InstanceDeletionException implements Exception {
  const InstanceDeletionException(this.stage, this.cause);

  final InstanceDeletionStage stage;
  final Object cause;

  String get userMessage => switch (stage) {
        InstanceDeletionStage.stoppingProcesses =>
          '无法停止正在运行的实例，尚未删除任何数据：$cause',
        InstanceDeletionStage.deletingDirectory =>
          '实例目录清理失败，本地记录和密钥均已保留，可稍后重试：$cause',
        InstanceDeletionStage.deletingSecret =>
          '实例目录已清理，但密钥清理失败；本地记录已保留，可重试：$cause',
        InstanceDeletionStage.removingRecord =>
          '实例目录和密钥已清理，但本地记录移除失败，可重试：$cause',
      };

  @override
  String toString() => userMessage;
}

final instanceDeletionServiceProvider =
    FutureProvider<InstanceDeletionService>((ref) async {
  final repository = await ref.watch(instanceRepositoryProvider.future);
  final runtime = ref.watch(runtimeBridgeProvider);
  return InstanceDeletionService(
    deleteDirectory: (instance) async {
      final result = await runtime.runInstallTask(
        'deleteInstance',
        args: <String, String>{'installDir': instance.installDir},
      );
      if (!result.success) {
        throw StateError(result.error ?? '原生层未能删除实例目录');
      }
    },
    deleteWebuiKey: WebuiKeyStore.delete,
    removeRecord: repository.remove,
  );
});
