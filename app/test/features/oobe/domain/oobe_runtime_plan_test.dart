import 'package:flutter_test/flutter_test.dart';
import 'package:mofox_android/features/oobe/domain/oobe_step.dart';

void main() {
  test('SnowLuma is absent from the default OOBE runtime plan', () {
    final tasks = oobeRuntimeTasks(installSnowluma: false);

    expect(
      tasks.map((task) => task.nativeName),
      <String>['extractRootfs', 'installRuntimeDeps'],
    );
  });

  test('SnowLuma install and verification are appended when selected', () {
    final tasks = oobeRuntimeTasks(installSnowluma: true);

    expect(
      tasks.map((task) => task.nativeName),
      <String>[
        'extractRootfs',
        'installRuntimeDeps',
        'installSnowluma',
        'verifySnowluma',
      ],
    );
  });
}
