import 'package:flutter_test/flutter_test.dart';
import 'package:mofox_android/features/assistant/application/assistant_notifier.dart';
import 'package:mofox_android/features/assistant/domain/assistant_models.dart';

void main() {
  test('conversation history is bounded to the most recent 100 messages', () {
    final messages = List<AssistantMessage>.generate(
      120,
      (index) => AssistantMessage(
        role: AssistantRole.user,
        text: '$index',
      ),
    );

    final state = AssistantState.initial().copyWith(messages: messages);

    expect(state.messages, hasLength(100));
    expect(state.messages.first.text, '20');
    expect(state.messages.last.text, '119');
  });
}
