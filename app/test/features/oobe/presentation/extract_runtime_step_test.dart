import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mofox_android/features/oobe/application/oobe_flow_notifier.dart';
import 'package:mofox_android/features/oobe/presentation/widgets/extract_runtime_step.dart';

void main() {
  testWidgets('NapCat is opt-in and can be selected before installation', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: ExtractRuntimeStep()),
        ),
      ),
    );

    expect(find.text('安装 NapCat（可选）'), findsOneWidget);
    expect(container.read(oobeFlowProvider).installNapcat, isFalse);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );

    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();

    expect(container.read(oobeFlowProvider).installNapcat, isTrue);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
  });
}
