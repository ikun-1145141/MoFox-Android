import 'package:flutter_test/flutter_test.dart';
import 'package:mofox_android/features/assistant/domain/assistant_models.dart';

void main() {
  test('decodes a structured command action and hides its envelope', () {
    final reply = AssistantAction.decodeReply('''
磁盘空间可以先这样检查。
<mofox_action>{"type":"command","command":"df -h","reason":"查看磁盘占用"}</mofox_action>
''');

    expect(reply.text, '磁盘空间可以先这样检查。');
    expect(reply.action?.type, AssistantActionType.command);
    expect(reply.action?.command, 'df -h');
  });

  test('ignores malformed or unknown actions', () {
    final malformed = AssistantAction.decodeReply(
      '说明<mofox_action>{bad json}</mofox_action>',
    );
    final unknown = AssistantAction.decodeReply(
      '说明<mofox_action>{"type":"delete_all"}</mofox_action>',
    );

    expect(malformed.action, isNull);
    expect(unknown.action, isNull);
    expect(malformed.text, '说明');
  });

  test('action-only replies still create an assistant history turn', () {
    final reply = AssistantAction.decodeReply(
      '<mofox_action>{"type":"command","command":"pwd",'
      '"reason":"确认工作目录"}</mofox_action>',
    );

    expect(reply.text, isEmpty);
    expect(reply.historyText, '准备执行：确认工作目录');
  });

  test('decodes a live documentation MCP tool call', () {
    final reply = AssistantAction.decodeReply(
      '<mofox_action>{"type":"mcp_tool",'
      '"name":"search_mofox_docs",'
      '"arguments":{"query":"模型配置","limit":3},'
      '"reason":"查询官方说明"}</mofox_action>',
    );

    expect(reply.action?.type, AssistantActionType.mcpTool);
    expect(reply.action?.toolName, 'search_mofox_docs');
    expect(reply.action?.arguments['query'], '模型配置');
  });
}
