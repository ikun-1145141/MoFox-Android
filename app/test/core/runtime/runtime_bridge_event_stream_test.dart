import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mofox_android/core/runtime/runtime_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('runtime topics share one native EventChannel subscription', () async {
    const codec = StandardMethodCodec();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var listenCount = 0;
    var cancelCount = 0;
    messenger.setMockMessageHandler('mofox/runtime/events', (message) async {
      final call = codec.decodeMethodCall(message);
      if (call.method == 'listen') listenCount++;
      if (call.method == 'cancel') cancelCount++;
      return codec.encodeSuccessEnvelope(null);
    });
    addTearDown(() {
      messenger.setMockMessageHandler('mofox/runtime/events', null);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final runtime = container.read(runtimeBridgeProvider);

    final processSubscription = runtime.processEvents().listen((_) {});
    final installSubscription = runtime.installEvents().listen((_) {});
    await Future<void>.delayed(Duration.zero);

    expect(listenCount, 1);
    expect(cancelCount, 0);

    await installSubscription.cancel();
    await Future<void>.delayed(Duration.zero);
    expect(cancelCount, 0);

    await processSubscription.cancel();
    await Future<void>.delayed(Duration.zero);
    expect(cancelCount, 1);
  });
}
