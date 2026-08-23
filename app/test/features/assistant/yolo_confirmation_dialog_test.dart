import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mofox_android/features/assistant/presentation/assistant_settings_page.dart';

void main() {
  testWidgets('YOLO confirmation fits with large text and the keyboard open',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.3),
            viewInsets: const EdgeInsets.only(bottom: 300),
          ),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showDialog<bool>(
                  context: context,
                  builder: (_) => const YoloConfirmationDialog(),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '确认开启'))
          .onPressed,
      isNull,
    );

    await tester.enterText(find.byType(TextField), '开启 YOLO');
    await tester.pump();

    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '确认开启'))
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('确认开启'));
    await tester.pumpAndSettle();
    expect(find.byType(YoloConfirmationDialog), findsNothing);
  });
}
