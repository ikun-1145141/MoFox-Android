import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mofox_android/features/backup/presentation/backup_page.dart';
import 'package:mofox_android/features/instance/application/instance_repository.dart';
import 'package:mofox_android/features/instance/domain/instance.dart';

void main() {
  testWidgets('default selection is real and refreshes by instance id', (
    tester,
  ) async {
    final source = StateProvider<List<Instance>>(
      (_) => <Instance>[_instance('first'), _instance('second')],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          instancesProvider.overrideWith(
            (ref) async => ref.watch(source),
          ),
        ],
        child: const MaterialApp(home: BackupPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(_dropdown(tester).value, 'first');

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('second (second-qq)').last);
    await tester.pumpAndSettle();
    expect(_dropdown(tester).value, 'second');

    final context = tester.element(find.byType(BackupPage));
    final container = ProviderScope.containerOf(context);
    container.read(source.notifier).state = <Instance>[
      _instance('first'),
      _instance('second'),
    ];
    await tester.pumpAndSettle();
    expect(_dropdown(tester).value, 'second');

    container.read(source.notifier).state = <Instance>[_instance('first')];
    await tester.pumpAndSettle();
    expect(_dropdown(tester).value, 'first');
  });
}

DropdownButton<String> _dropdown(WidgetTester tester) {
  return tester.widget<DropdownButton<String>>(
    find.byType(DropdownButton<String>),
  );
}

Instance _instance(String id) => Instance(
      id: id,
      name: id,
      botQq: '$id-qq',
      botNickname: id,
      ownerQq: 'owner',
      wsPort: id == 'first' ? 8095 : 8096,
      channel: 'main',
      installNapcat: true,
      installWebui: true,
      installDir: '/root/instances/$id',
      createdAt: DateTime.utc(2026),
    );
