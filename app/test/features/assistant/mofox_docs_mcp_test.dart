import 'package:flutter_test/flutter_test.dart';
import 'package:mofox_android/features/assistant/data/mofox_docs_mcp.dart';

void main() {
  const runLive = bool.fromEnvironment('MOFOX_LIVE_DOCS_TEST');

  test('live docs MCP initializes and exposes its read-only tools', () async {
    final tools = await MofoxDocsMcpClient().listTools();

    expect(
      tools.map((tool) => tool['name']),
      <String>['search_mofox_docs', 'read_mofox_doc'],
    );
  });

  test('live docs MCP refuses non-official read URLs before fetching',
      () async {
    await expectLater(
      MofoxDocsMcpClient().callTool(
        'read_mofox_doc',
        <String, Object?>{'url': 'https://example.com/fake-docs'},
      ),
      throwsA(isA<StateError>()),
    );
  });

  test(
    'live docs MCP searches and reads the current official website',
    () async {
      final client = MofoxDocsMcpClient();
      for (final query in <String>['Android 官方部署', '模型配置', '维护指南']) {
        final search = await client.callTool(
          'search_mofox_docs',
          <String, Object?>{'query': query, 'limit': 2},
        );
        expect(search, contains('docs.mofox-sama.com'));
        final url = RegExp(r'https://docs\.mofox-sama\.com/\S+')
            .firstMatch(search)!
            .group(0)!;
        final page = await client.callTool(
          'read_mofox_doc',
          <String, Object?>{'url': url, 'max_chars': 1200},
        );
        expect(page, contains('来源：https://docs.mofox-sama.com'));
        expect(page.length, greaterThan(100));
      }
    },
    skip: runLive ? false : 'set MOFOX_LIVE_DOCS_TEST=true',
  );
}
