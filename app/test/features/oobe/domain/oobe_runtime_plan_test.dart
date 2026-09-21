import 'package:flutter_test/flutter_test.dart';
import 'package:mofox_android/features/oobe/domain/oobe_step.dart';

void main() {
  test('NapCat is absent from the default OOBE runtime plan', () {
    final tasks = oobeRuntimeTasks(installNapcat: false);

    expect(
      tasks.map((task) => task.nativeName),
      <String>['extractRootfs', 'installRuntimeDeps'],
    );
  });

  test('NapCat install and verification are appended when selected', () {
    final tasks = oobeRuntimeTasks(installNapcat: true);

    expect(
      tasks.map((task) => task.nativeName),
      <String>[
        'extractRootfs',
        'installRuntimeDeps',
        'installNapcat',
        'verifyNapcat',
      ],
    );
  });
}
