import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mofox_android/core/theme/app_theme.dart';
import 'package:mofox_android/features/settings/presentation/third_party_licenses_page.dart';

void main() {
  testWidgets('license list and detail fit narrow screens with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const item = ThirdPartyLicenseItem(
      packageName: 'example_package',
      paragraphs: <LicenseParagraph>[
        LicenseParagraph('Example license text.', 0),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          thirdPartyLicensesProvider.overrideWith(
            (ref) async => const ThirdPartyLicenseBundle(
              version: '1.0.0 (1)',
              items: <ThirdPartyLicenseItem>[item],
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: const TextScaler.linear(1.5),
            ),
            child: child!,
          ),
          home: const ThirdPartyLicensesPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 个许可包'), findsOneWidget);
    await tester.ensureVisible(find.text('example_package'));
    await tester.tap(find.text('example_package'));
    await tester.pumpAndSettle();

    expect(find.text('Example license text.'), findsOneWidget);
    final copy = find.widgetWithText(FilledButton, '复制许可文本');
    expect(tester.getSize(copy).height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  });
}
