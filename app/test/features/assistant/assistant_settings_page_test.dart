import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mofox_android/core/theme/app_theme.dart';
import 'package:mofox_android/features/assistant/application/assistant_settings_notifier.dart';
import 'package:mofox_android/features/assistant/presentation/assistant_settings_page.dart';

void main() {
  testWidgets('connection form validates insecure URLs on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          assistantSettingsProvider.overrideWith(
            _FakeAssistantSettingsNotifier.new,
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const AssistantSettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'http://example.com/v1');
    await tester.enterText(fields.at(1), 'test-model');
    await tester.enterText(fields.at(2), 'secret');

    final save = find.widgetWithText(FilledButton, '保存');
    final test = find.widgetWithText(OutlinedButton, '保存并测试');
    expect(tester.getTopLeft(save).dy, greaterThan(tester.getTopLeft(test).dy));

    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pump();

    expect(find.text('HTTP 未加密；请改用 HTTPS 或先开启“不安全 HTTP”'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FakeAssistantSettingsNotifier extends AssistantSettingsNotifier {
  @override
  Future<AssistantSettings> build() async => const AssistantSettings(
        enabled: false,
        baseUrl: '',
        model: '',
        mode: AssistantOperationMode.copilot,
        hasApiKey: false,
        yoloConsentVersion: 0,
        allowInsecureHttp: false,
      );
}
