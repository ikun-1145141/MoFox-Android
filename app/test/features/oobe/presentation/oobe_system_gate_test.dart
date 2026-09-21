import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mofox_android/features/dashboard/domain/system_stats.dart';
import 'package:mofox_android/features/oobe/application/system_check_provider.dart';
import 'package:mofox_android/features/oobe/presentation/oobe_page.dart';

void main() {
  testWidgets('system check blocks next until real requirements pass',
      (tester) async {
    final stats = Completer<SystemStats>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          systemStatsLoaderProvider.overrideWithValue(() => stats.future),
        ],
        child: const MaterialApp(home: OobePage()),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('同意并继续'));
    await tester.pump();

    var next = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '下一步'),
    );
    expect(next.onPressed, isNull);

    stats.complete(_passingStats());
    await tester.pumpAndSettle();

    next = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '下一步'),
    );
    expect(next.onPressed, isNotNull);
  });
}

SystemStats _passingStats() => const SystemStats(
      socName: 'test',
      memoryTotal: 4 * 1024 * 1024 * 1024,
      memoryAvailable: 2 * 1024 * 1024 * 1024,
      memoryUsed: 2 * 1024 * 1024 * 1024,
      storageTotal: 16 * 1024 * 1024 * 1024,
      storageAvailable: 8 * 1024 * 1024 * 1024,
      storageUsed: 8 * 1024 * 1024 * 1024,
      appDataTotal: 16 * 1024 * 1024 * 1024,
      appDataAvailable: 8 * 1024 * 1024 * 1024,
      deviceName: 'test',
      androidVersion: '14',
      sdkInt: 34,
      supportedAbis: 'arm64-v8a',
      kernel: 'test',
      rootfsPath: '/data/test/usr',
      appDataPath: '/data/test',
    );
