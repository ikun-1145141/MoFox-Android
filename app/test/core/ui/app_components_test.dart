import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mofox_android/core/theme/app_theme.dart';
import 'package:mofox_android/core/ui/app_components.dart';

void main() {
  testWidgets('page content is centered and constrained on wide screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const contentKey = Key('content');

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: AppPageList(
            children: <Widget>[
              SizedBox(key: contentKey, height: 40),
            ],
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byKey(contentKey)).width, 840);
  });

  testWidgets('settings tiles keep a minimum accessible touch height', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: AppSettingTile(
            title: '可点击设置',
            onTap: () => taps++,
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(ListTile)).height,
      greaterThanOrEqualTo(64),
    );
    await tester.tap(find.text('可点击设置'));
    expect(taps, 1);
  });

  testWidgets('error state announces itself and keeps retry accessible', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var retries = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: AppErrorState(onRetry: () => retries++),
        ),
      ),
    );

    expect(find.bySemanticsLabel('加载失败，请检查后重试。'), findsOneWidget);
    expect(find.bySemanticsLabel('重试'), findsOneWidget);
    await tester.tap(find.text('重试'));
    expect(retries, 1);
    semantics.dispose();
  });

  testWidgets('status badge exposes a text status instead of color alone', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: Center(
            child: AppStatusBadge(
              label: '运行中',
              tone: AppStatusTone.success,
            ),
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('状态：运行中'), findsOneWidget);
    expect(find.text('运行中'), findsOneWidget);
    semantics.dispose();
  });

  test('theme uses 48dp actions and a high contrast variant', () {
    final regular = AppTheme.light();
    final highContrast = AppTheme.highContrastLight();
    final textButtonMinimum = regular.textButtonTheme.style?.minimumSize
        ?.resolve(const <WidgetState>{});

    expect(textButtonMinimum?.height, 48);
    expect(regular.inputDecorationTheme.filled, isTrue);
    expect(
      highContrast.colorScheme.primary,
      isNot(regular.colorScheme.primary),
    );
  });
}
