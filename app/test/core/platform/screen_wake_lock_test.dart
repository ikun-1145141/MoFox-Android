import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mofox_android/core/platform/screen_wake_lock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestDefaultBinaryMessenger messenger;
  late List<bool> values;

  setUp(() {
    messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    values = <bool>[];
    messenger.setMockMethodCallHandler(
      const MethodChannel('mofox/platform'),
      (call) async {
        if (call.method == 'setKeepScreenOn') {
          final arguments = call.arguments! as Map<Object?, Object?>;
          values.add(arguments['enabled']! as bool);
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

  test('overlapping operations hold one wake lock until both complete',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(screenWakeLockProvider);
    final firstStarted = Completer<void>();
    final secondStarted = Completer<void>();
    final finishFirst = Completer<void>();
    final finishSecond = Completer<void>();

    final first = controller.keepAwakeWhile(() async {
      firstStarted.complete();
      await finishFirst.future;
    });
    await firstStarted.future;
    final second = controller.keepAwakeWhile(() async {
      secondStarted.complete();
      await finishSecond.future;
    });
    await secondStarted.future;

    expect(values, <bool>[true]);
    finishFirst.complete();
    await first;
    expect(values, <bool>[true]);

    finishSecond.complete();
    await second;
    expect(values, <bool>[true, false]);
  });

  test('wake lock is released when the protected operation throws', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(screenWakeLockProvider);

    await expectLater(
      controller.keepAwakeWhile<void>(() async => throw StateError('failed')),
      throwsStateError,
    );

    expect(values, <bool>[true, false]);
  });
}
