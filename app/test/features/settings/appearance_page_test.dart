import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mofox_android/core/theme/app_theme.dart';
import 'package:mofox_android/features/settings/presentation/appearance_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('appearance controls fit a narrow screen with reduced motion', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: const TextScaler.linear(1.2),
            ),
            child: child!,
          ),
          home: const AppearancePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('主题模式'), findsOneWidget);
    expect(find.text('动态取色'), findsWidgets);
    expect(find.text('隐藏主图'), findsOneWidget);
    expect(
      tester.widget<AnimatedContainer>(find.byType(AnimatedContainer)).duration,
      Duration.zero,
    );
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('隐藏主图'));
    await tester.pump();
    await tester.tap(find.text('隐藏主图'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
