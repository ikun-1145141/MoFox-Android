import 'package:flutter_test/flutter_test.dart';
import 'package:mofox_android/features/assistant/data/assistant_api_client.dart';
import 'package:mofox_android/features/assistant/domain/assistant_models.dart';

void main() {
  test('tool results do not add a second system role to API history', () {
    final payload = AssistantApiClient().buildChatPayload(
      model: 'test-model',
      systemPrompt: 'system prompt',
      messages: const <AssistantMessage>[
        AssistantMessage(role: AssistantRole.user, text: '检查目录'),
        AssistantMessage(role: AssistantRole.assistant, text: '准备执行 pwd'),
        AssistantMessage(role: AssistantRole.system, text: '工具执行结果：/root'),
      ],
    );
    final messages = payload['messages']! as List<Map<String, String>>;

    expect(messages.map((item) => item['role']), <String>[
      'system',
      'user',
      'assistant',
      'user',
    ]);
    expect(messages.last['content'], contains('/root'));
    expect(
      messages.where((item) => item['role'] == 'system'),
      hasLength(1),
    );
  });
}
