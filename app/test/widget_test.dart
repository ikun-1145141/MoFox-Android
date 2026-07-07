import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mofox_android/app/mofox_app.dart';

void main() {
  testWidgets('App boots without crashing', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MoFoxApp()));
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
