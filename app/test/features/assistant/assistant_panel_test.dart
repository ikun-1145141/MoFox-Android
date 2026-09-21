import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mofox_android/features/assistant/domain/assistant_models.dart';
import 'package:mofox_android/features/assistant/presentation/assistant_panel.dart';

void main() {
  testWidgets('completed execution output is collapsed and can be expanded',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AssistantExecutionCard(
            running: false,
            output: 'command output',
          ),
        ),
      ),
    );

    expect(find.text('command output'), findsNothing);
    expect(find.text('展开'), findsOneWidget);

    await tester.tap(find.text('展开'));
    await tester.pump();

    expect(find.text('command output'), findsOneWidget);
    expect(find.text('收起'), findsOneWidget);
  });

  testWidgets('message actions fit large text and use native selection',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var retries = 0;
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText =
              (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.3),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: AssistantMessageBubble(
            message: const AssistantMessage(
              role: AssistantRole.assistant,
              text: '这是一条可以选择和复制的回复。',
            ),
            onRetry: () => retries++,
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.widgetWithText(TextButton, '选择')).height,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester.getSize(find.widgetWithText(TextButton, '复制')).height,
      greaterThanOrEqualTo(48),
    );
    await tester.tap(find.text('复制'));
    await tester.pumpAndSettle();
    expect(copiedText, '这是一条可以选择和复制的回复。');

    await tester.tap(find.text('重试'));
    expect(retries, 1);

    await tester.tap(find.text('选择'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
