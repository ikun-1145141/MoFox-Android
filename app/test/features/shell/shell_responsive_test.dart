import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mofox_android/app/mofox_app.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('uses Material 3 bar on phone and rail on larger windows',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'oobe_done': true,
    });
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const ProviderScope(child: MoFoxApp()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('实例'), findsOneWidget);

    await tester.binding.setSurfaceSize(const Size(900, 800));
    await tester.pump();

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(NavigationRail), findsOneWidget);
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.extended, isFalse);

    await tester.binding.setSurfaceSize(const Size(1280, 800));
    await tester.pump();

    final extendedRail =
        tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(extendedRail.extended, isTrue);
    expect(find.text('MoFox'), findsOneWidget);
  });
}
