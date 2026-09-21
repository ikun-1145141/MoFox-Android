import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mofox_android/features/dashboard/domain/system_stats.dart';
import 'package:mofox_android/features/oobe/application/system_check_provider.dart';

void main() {
  test('uses real stats and only passes when every requirement is met',
      () async {
    final container = ProviderContainer(
      overrides: <Override>[
        systemStatsLoaderProvider.overrideWithValue(
          () async => _stats(),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(systemCheckProvider, (_, __) {});

    await _waitForCheck(container);

    final result = container.read(systemCheckProvider);
    expect(result.running, isFalse);
    expect(result.allPassed, isTrue);
    expect(
      result.items.map((item) => item.status),
      everyElement(SystemCheckStatus.passed),
    );
  });

  test('reports unavailable platform data as unknown instead of passed',
      () async {
    final container = ProviderContainer(
      overrides: <Override>[
        systemStatsLoaderProvider.overrideWithValue(
          () async => throw StateError('channel unavailable'),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(systemCheckProvider, (_, __) {});

    await _waitForCheck(container);

    final result = container.read(systemCheckProvider);
    expect(result.allPassed, isFalse);
    expect(result.hasUnknown, isTrue);
    expect(
      result.items.map((item) => item.status),
      everyElement(SystemCheckStatus.unknown),
    );
  });

  test('fails measured values below the documented requirements', () async {
    final container = ProviderContainer(
      overrides: <Override>[
        systemStatsLoaderProvider.overrideWithValue(
          () async => _stats(
            supportedAbis: 'armeabi-v7a',
            appDataAvailable: 512 * 1024 * 1024,
            memoryAvailable: 256 * 1024 * 1024,
            sdkInt: 23,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(systemCheckProvider, (_, __) {});

    await _waitForCheck(container);

    final result = container.read(systemCheckProvider);
    expect(result.allPassed, isFalse);
    expect(
      result.items.map((item) => item.status),
      everyElement(SystemCheckStatus.failed),
    );
  });
}

Future<void> _waitForCheck(ProviderContainer container) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    if (!container.read(systemCheckProvider).running) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('system check did not finish');
}

SystemStats _stats({
  String supportedAbis = 'arm64-v8a, armeabi-v7a',
  int appDataAvailable = 4 * 1024 * 1024 * 1024,
  int memoryAvailable = 2 * 1024 * 1024 * 1024,
  int sdkInt = 34,
}) =>
    SystemStats(
      socName: 'test',
      memoryTotal: 4 * 1024 * 1024 * 1024,
      memoryAvailable: memoryAvailable,
      memoryUsed: 2 * 1024 * 1024 * 1024,
      storageTotal: 16 * 1024 * 1024 * 1024,
      storageAvailable: appDataAvailable,
      storageUsed: 8 * 1024 * 1024 * 1024,
      appDataTotal: 16 * 1024 * 1024 * 1024,
      appDataAvailable: appDataAvailable,
      deviceName: 'test',
      androidVersion: '14',
      sdkInt: sdkInt,
      supportedAbis: supportedAbis,
      kernel: 'test',
      rootfsPath: '/data/test/usr',
      appDataPath: '/data/test',
    );
