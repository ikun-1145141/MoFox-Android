import 'dart:convert';

enum AssistantRole { user, assistant, system }

class AssistantMessage {
  const AssistantMessage({required this.role, required this.text});

  final AssistantRole role;
  final String text;

  Map<String, String> toApiJson() => <String, String>{
        'role': role.name,
        'content': text,
      };
}

enum AssistantActionType { command, restartBot, restartNapcat, mcpTool }

class AssistantAction {
  const AssistantAction({
    required this.type,
    required this.reason,
    this.command,
    this.toolName,
    this.arguments = const <String, Object?>{},
  });

  final AssistantActionType type;
  final String reason;
  final String? command;
  final String? toolName;
  final Map<String, Object?> arguments;

  String get title => switch (type) {
        AssistantActionType.command => '运行终端命令',
        AssistantActionType.restartBot => '重启 Bot',
        AssistantActionType.restartNapcat => '重启 NapCat',
        AssistantActionType.mcpTool => '查询官方文档',
      };

  static AssistantDecodedReply decodeReply(String raw) {
    final match = RegExp(
      r'<mofox_action>\s*([\s\S]*?)\s*</mofox_action>',
      caseSensitive: false,
    ).firstMatch(raw);
    if (match == null) {
      return AssistantDecodedReply(text: raw.trim());
    }
    final visible = raw.replaceRange(match.start, match.end, '').trim();
    try {
      final json = jsonDecode(match.group(1)!) as Map<String, Object?>;
      final type = switch (json['type']) {
        'command' => AssistantActionType.command,
        'restart_bot' => AssistantActionType.restartBot,
        'restart_napcat' => AssistantActionType.restartNapcat,
        'mcp_tool' => AssistantActionType.mcpTool,
        _ => null,
      };
      if (type == null) return AssistantDecodedReply(text: visible);
      final command = json['command']?.toString().trim();
      if (type == AssistantActionType.command &&
          (command == null || command.isEmpty)) {
        return AssistantDecodedReply(text: visible);
      }
      final toolName = json['name']?.toString().trim();
      if (type == AssistantActionType.mcpTool &&
          !const <String>{'search_mofox_docs', 'read_mofox_doc'}
              .contains(toolName)) {
        return AssistantDecodedReply(text: visible);
      }
      final arguments = json['arguments'];
      if (type == AssistantActionType.mcpTool &&
          arguments is! Map<String, Object?>) {
        return AssistantDecodedReply(text: visible);
      }
      return AssistantDecodedReply(
        text: visible,
        action: AssistantAction(
          type: type,
          reason: json['reason']?.toString().trim().isNotEmpty == true
              ? json['reason']!.toString().trim()
              : 'AI 建议执行此操作',
          command: command,
          toolName: toolName,
          arguments: arguments is Map<String, Object?>
              ? arguments
              : const <String, Object?>{},
        ),
      );
    } on Object {
      return AssistantDecodedReply(text: visible);
    }
  }
}

class AssistantDecodedReply {
  const AssistantDecodedReply({required this.text, this.action});

  final String text;
  final AssistantAction? action;

  /// 保证模型历史中每个工具结果之前都有对应的 assistant 轮次。
  String get historyText {
    if (text.isNotEmpty) return text;
    final pending = action;
    if (pending == null) return '';
    return '准备执行：${pending.reason}';
  }
}

class AssistantCommandResult {
  const AssistantCommandResult({
    required this.exitCode,
    required this.output,
    required this.timedOut,
    required this.truncated,
  });

  final int exitCode;
  final String output;
  final bool timedOut;
  final bool truncated;

  bool get success => exitCode == 0 && !timedOut;

  factory AssistantCommandResult.fromMap(Map<Object?, Object?> map) {
    return AssistantCommandResult(
      exitCode: (map['exitCode'] as num?)?.toInt() ?? -1,
      output: map['output']?.toString() ?? '',
      timedOut: map['timedOut'] == true,
      truncated: map['truncated'] == true,
    );
  }
}
