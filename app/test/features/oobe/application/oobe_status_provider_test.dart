import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mofox_android/features/oobe/application/oobe_status_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('OOBE is incomplete until the explicit done flag is written', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await expectLater(
        container.read(oobeStatusProvider.future), completion(false));
  });

  test('OOBE is complete when the explicit done flag is true', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{'oobe_done': true});

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await expectLater(
        container.read(oobeStatusProvider.future), completion(true));
  });
}
