import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mofox_android/features/wizard/application/wizard_network_checks.dart';
import 'package:mofox_android/features/wizard/application/wizard_notifier.dart';

void main() {
  test('completes real probe state and selects the fastest reachable mirror',
      () async {
    final container = ProviderContainer(
      overrides: <Override>[
        mirrorProbeProvider.overrideWithValue(
          (source) async => MirrorProbeResult(
            mirror: source,
            reachable: source.id != 'ghproxy',
            latencyMs: source.id == 'ikun' ? 20 : 80,
            errorMessage: source.id == 'ghproxy' ? 'offline' : null,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(wizardProvider, (_, __) {});
    container.listen(mirrorCheckProvider, (_, __) {});

    await _waitForCheck(container);

    final check = container.read(mirrorCheckProvider);
    expect(check.completed, isTrue);
    expect(check.hasReachable, isTrue);
    expect(container.read(wizardProvider).draft.mirrorId, 'ikun');
  });

  test('does not claim completion success when every endpoint fails', () async {
    final container = ProviderContainer(
      overrides: <Override>[
        mirrorProbeProvider.overrideWithValue(
          (source) async => MirrorProbeResult(
            mirror: source,
            reachable: false,
            latencyMs: 10,
            errorMessage: 'timeout',
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(wizardProvider, (_, __) {});
    container.listen(mirrorCheckProvider, (_, __) {});

    await _waitForCheck(container);

    final check = container.read(mirrorCheckProvider);
    expect(check.completed, isTrue);
    expect(check.hasReachable, isFalse);
    expect(check.isReachable(container.read(wizardProvider).draft.mirrorId),
        isFalse);
  });
}

Future<void> _waitForCheck(ProviderContainer container) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    if (container.read(mirrorCheckProvider).completed) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('mirror check did not finish');
}
