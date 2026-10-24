import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mofox_android/core/runtime/runtime_bridge.dart';
import 'package:mofox_android/core/utils/app_logger.dart';

/// 「设置 → SnowLuma 管理目录」的维护逻辑。
///
/// SnowLuma 运行时全局唯一（/root/snowluma），所有实例共享；本 provider
/// 只负责安装/校验任务的执行与日志流。进程启停走 processConsoleProvider
/// 的既有方法（restartSnowluma），不在这里重复实现。
class SnowlumaMaintenanceState {
  const SnowlumaMaintenanceState({
    this.logs = const <String>[],
    this.running = false,
    this.lastResultMessage,
    this.installedVersion,
  });

  final List<String> logs;
  final bool running;

  /// 最近一次维护操作的结果提示（弹窗/SnackBar 文案）。
  final String? lastResultMessage;

  /// 从 verifySnowluma 的 MOFOX_SL_VERSION= 输出解析的已安装版本。
  final String? installedVersion;

  SnowlumaMaintenanceState copyWith({
    List<String>? logs,
    bool? running,
    Object? lastResultMessage = _sentinel,
    Object? installedVersion = _sentinel,
  }) =>
      SnowlumaMaintenanceState(
        logs: logs ?? this.logs,
        running: running ?? this.running,
        lastResultMessage: identical(lastResultMessage, _sentinel)
            ? this.lastResultMessage
            : lastResultMessage as String?,
        installedVersion: identical(installedVersion, _sentinel)
            ? this.installedVersion
            : installedVersion as String?,
      );
}

const Object _sentinel = Object();

class SnowlumaMaintenanceNotifier
    extends Notifier<SnowlumaMaintenanceState> {
  @override
  SnowlumaMaintenanceState build() => SnowlumaMaintenanceState();

  void _appendLog(String line) {
    state = state.copyWith(logs: <String>[...state.logs, line]);
  }

  /// 解析任务输出里的 MOFOX_SL_VERSION= 行。
  String? _parseVersion(List<String> logs) {
    for (final line in logs.reversed) {
      if (line.startsWith('MOFOX_SL_VERSION=')) {
        final value = line.substring('MOFOX_SL_VERSION='.length).trim();
        if (value.isNotEmpty) return value;
      }
    }
    return null;
  }

  /// 轻量读取当前安装状态（只跑 verifySnowluma 纯文件检查，秒级）。
  Future<void> refreshInstalledVersion() async {
    final runtime = ref.read(runtimeBridgeProvider);
    try {
      final result = await runtime.runInstallTask('verifySnowluma');
      final version = _parseVersion(result.logs);
      state = state.copyWith(
        installedVersion:
            version ?? (result.success ? state.installedVersion : '未安装'),
      );
    } on Object catch (error) {
      appLogger.w('snowluma maintenance: read version failed: $error');
    }
  }

  /// 检查并修复：幂等跑 installSnowluma + verifySnowluma。
  ///
  /// 健康设备秒级"跳过重装"；标记缺失/文件损坏时走完整安装。
  /// 返回是否成功；结果文案写入 [SnowlumaMaintenanceState.lastResultMessage]。
  Future<bool> checkAndRepair() async {
    if (state.running) return false;
    final runtime = ref.read(runtimeBridgeProvider);
    state = state.copyWith(
      running: true,
      logs: <String>[...state.logs, '[control] 开始检查并修复 SnowLuma…'],
      lastResultMessage: null,
    );
    const taskNames = <String>['installSnowluma', 'verifySnowluma'];
    final streamedTasks = <String>{};
    final subscription = runtime
        .installEvents()
        .where((event) => taskNames.contains(event.task))
        .listen((event) {
      streamedTasks.add(event.task);
      _appendLog(event.line);
    });
    var success = true;
    try {
      for (final task in taskNames) {
        final label = task == 'installSnowluma' ? '准备 SnowLuma' : '校验 SnowLuma';
        _appendLog('[control] $label…');
        final result = await runtime.runInstallTask(task);
        if (!streamedTasks.contains(task)) {
          for (final line in result.logs) {
            _appendLog(line);
          }
        }
        if (!result.success) {
          success = false;
          _appendLog('[control] $label失败：${result.error ?? '未知错误'}');
          break;
        }
        _appendLog('[control] $label完成');
      }
    } on Object catch (error) {
      success = false;
      _appendLog('[control] 维护任务异常：$error');
    } finally {
      await subscription.cancel();
    }
    String message;
    if (success) {
      // MOFOX_SL_VERSION= 行可能走事件流（result.logs 为空），从累积日志解析。
      final version = _parseVersion(state.logs) ?? state.installedVersion;
      if (version != null) {
        state = state.copyWith(installedVersion: version);
      }
      message = '检查并修复完成。若本次安装了新版本，'
          '需重启 SnowLuma 后才能生效（可用下方「重启 SnowLuma」）。'
          '${version == null ? '' : '当前版本：$version'}';
    } else {
      message = '修复失败，详见日志。可检查网络后重试。';
    }
    state = state.copyWith(
      running: false,
      lastResultMessage: message,
    );
    return success;
  }
}

final snowlumaMaintenanceProvider =
    NotifierProvider<SnowlumaMaintenanceNotifier, SnowlumaMaintenanceState>(
  SnowlumaMaintenanceNotifier.new,
);
