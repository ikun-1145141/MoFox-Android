import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mofox_android/core/platform/platform_gateway.dart';
import 'package:mofox_android/core/theme/app_theme.dart';
import 'package:mofox_android/features/settings/presentation/keepalive_status_page.dart';

void main() {
  testWidgets('status actions wrap without overflow on a narrow large-text UI',
      (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          keepaliveStatusProvider.overrideWith(
            (ref) async => const KeepaliveStatus(
              notificationsGranted: false,
              ignoringBatteryOptimizations: false,
              foregroundServiceEnabled: false,
              bootReceiverDeclared: true,
              vendorAutostartInspectable: false,
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.5),
            ),
            child: child!,
          ),
          home: const KeepaliveStatusPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('待处理'), findsOneWidget);
    expect(find.text('未授权'), findsOneWidget);
    expect(find.text('需手动确认'), findsOneWidget);
    final action = find.widgetWithText(FilledButton, '去授权');
    expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  });
}
