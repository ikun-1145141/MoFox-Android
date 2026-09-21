import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/runtime/runtime_bridge.dart';
import '../../dashboard/domain/system_stats.dart';

const int _minimumStorageBytes = 2 * 1024 * 1024 * 1024;
const int _minimumAvailableMemoryBytes = 1024 * 1024 * 1024;
const int _minimumAndroidSdk = 24;

enum SystemCheckStatus { checking, passed, failed, unknown }

class SystemCheckResult {
  const SystemCheckResult({
    required this.label,
    required this.value,
    required this.status,
  });

  final String label;
  final String value;
  final SystemCheckStatus status;
}

class SystemCheckState {
  const SystemCheckState({
    required this.items,
    required this.running,
    this.errorMessage,
  });

  final List<SystemCheckResult> items;
  final bool running;
  final String? errorMessage;

  bool get completed => !running;
  bool get allPassed =>
      completed &&
      items.isNotEmpty &&
      items.every((item) => item.status == SystemCheckStatus.passed);

  bool get hasUnknown =>
      items.any((item) => item.status == SystemCheckStatus.unknown);
}

typedef SystemStatsLoader = Future<SystemStats> Function();

/// 可覆写的设备信息入口，让体检逻辑在测试中无需伪造平台通道。
final systemStatsLoaderProvider = Provider<SystemStatsLoader>((ref) {
  final runtime = ref.watch(runtimeBridgeProvider);
  return runtime.systemStats;
});

final systemCheckProvider =
    NotifierProvider<SystemCheckNotifier, SystemCheckState>(
  SystemCheckNotifier.new,
);

class SystemCheckNotifier extends Notifier<SystemCheckState> {
  int _generation = 0;

  @override
  SystemCheckState build() {
    Future<void>.microtask(run);
    return _checkingState;
  }

  Future<void> run() async {
    final generation = ++_generation;
    state = _checkingState;
    try {
      final stats = await ref.read(systemStatsLoaderProvider)().timeout(
            const Duration(seconds: 8),
          );
      if (generation != _generation) return;
      state = SystemCheckState(
        running: false,
        items: _resultsFrom(stats),
      );
    } on Object catch (error) {
      if (generation != _generation) return;
      state = SystemCheckState(
        running: false,
        errorMessage: '无法读取设备信息：$error',
        items: const <SystemCheckResult>[
          SystemCheckResult(
            label: 'CPU 架构',
            value: '未检测',
            status: SystemCheckStatus.unknown,
          ),
          SystemCheckResult(
            label: '应用可用空间',
            value: '未检测',
            status: SystemCheckStatus.unknown,
          ),
          SystemCheckResult(
            label: '可用内存',
            value: '未检测',
            status: SystemCheckStatus.unknown,
          ),
          SystemCheckResult(
            label: 'Android 版本',
            value: '未检测',
            status: SystemCheckStatus.unknown,
          ),
        ],
      );
    }
  }
}

const SystemCheckState _checkingState = SystemCheckState(
  running: true,
  items: <SystemCheckResult>[
    SystemCheckResult(
      label: 'CPU 架构',
      value: '正在检测…',
      status: SystemCheckStatus.checking,
    ),
    SystemCheckResult(
      label: '应用可用空间',
      value: '正在检测…',
      status: SystemCheckStatus.checking,
    ),
    SystemCheckResult(
      label: '可用内存',
      value: '正在检测…',
      status: SystemCheckStatus.checking,
    ),
    SystemCheckResult(
      label: 'Android 版本',
      value: '正在检测…',
      status: SystemCheckStatus.checking,
    ),
  ],
);

List<SystemCheckResult> _resultsFrom(SystemStats stats) {
  final abis = stats.supportedAbis.trim();
  final architectureStatus = abis.isEmpty || abis == 'Unknown'
      ? SystemCheckStatus.unknown
      : abis.split(',').map((value) => value.trim()).contains('arm64-v8a')
          ? SystemCheckStatus.passed
          : SystemCheckStatus.failed;

  final storage = stats.appDataAvailable > 0
      ? stats.appDataAvailable
      : stats.storageAvailable;
  final storageStatus = storage <= 0
      ? SystemCheckStatus.unknown
      : storage >= _minimumStorageBytes
          ? SystemCheckStatus.passed
          : SystemCheckStatus.failed;

  final memoryStatus = stats.memoryAvailable <= 0
      ? SystemCheckStatus.unknown
      : stats.memoryAvailable >= _minimumAvailableMemoryBytes
          ? SystemCheckStatus.passed
          : SystemCheckStatus.failed;

  final androidStatus = stats.sdkInt <= 0
      ? SystemCheckStatus.unknown
      : stats.sdkInt >= _minimumAndroidSdk
          ? SystemCheckStatus.passed
          : SystemCheckStatus.failed;

  return <SystemCheckResult>[
    SystemCheckResult(
      label: 'CPU 架构',
      value: architectureStatus == SystemCheckStatus.unknown ? '未检测' : abis,
      status: architectureStatus,
    ),
    SystemCheckResult(
      label: '应用可用空间',
      value: storageStatus == SystemCheckStatus.unknown
          ? '未检测'
          : '${_formatGiB(storage)} 可用（需 2 GB）',
      status: storageStatus,
    ),
    SystemCheckResult(
      label: '可用内存',
      value: memoryStatus == SystemCheckStatus.unknown
          ? '未检测'
          : '${_formatGiB(stats.memoryAvailable)} 可用（需 1 GB）',
      status: memoryStatus,
    ),
    SystemCheckResult(
      label: 'Android 版本',
      value: androidStatus == SystemCheckStatus.unknown
          ? '未检测'
          : '${stats.androidVersion}（API ${stats.sdkInt}，需 API 24）',
      status: androidStatus,
    ),
  ];
}

String _formatGiB(int bytes) {
  final gib = bytes / (1024 * 1024 * 1024);
  return '${gib.toStringAsFixed(gib >= 10 ? 0 : 1)} GB';
}
