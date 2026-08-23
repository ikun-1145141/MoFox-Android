import '../domain/assistant_models.dart';

enum AssistantPolicyDecision { allow, manualOnly, deny }

class AssistantPolicyResult {
  const AssistantPolicyResult(this.decision, this.reason);

  final AssistantPolicyDecision decision;
  final String reason;
}

class AssistantPolicy {
  const AssistantPolicy();

  static final RegExp _controlCharacters = RegExp(r'[\x00-\x1f\x7f]');
  static final RegExp _shellOperators = RegExp(r'[;&|><`]|\$\(');
  static final RegExp _hardDenied = RegExp(
    r'(^|\s)(rm\s+(-[^\s]*[rR][^\s]*\s+|--recursive\s+)|mkfs\b|fdisk\b|parted\b|mount\b|umount\b|dd\s+[^\n]*\bof=|shutdown\b|reboot\b|poweroff\b|chroot\b)|'
    r'(curl|wget)[^\n]*\|\s*(sh|bash)|'
    r'(/etc/(shadow|passwd)|\.ssh/|authorized_keys|api[_-]?key|password|token|cookie)',
    caseSensitive: false,
  );
  static final RegExp _privatePaths = RegExp(
    r'(^|\s)(/sdcard|/storage|/data|/dev|/sys|/proc/[^\s]*/(environ|cmdline)|/root/\.[^\s]*)',
    caseSensitive: false,
  );
  static final RegExp _parentTraversal = RegExp(r'(^|\s)\.\.(/|\s|$)');
  static const Set<String> _yoloExecutables = <String>{
    'pwd',
    'ls',
    'df',
    'du',
    'free',
    'uname',
    'id',
    'whoami',
    'date',
    'uptime',
    'git',
    'python',
    'python3',
    'pip',
    'pip3',
  };

  AssistantPolicyResult evaluate(
    AssistantAction action, {
    bool unrestricted = false,
  }) {
    if (action.type != AssistantActionType.command) {
      return const AssistantPolicyResult(
        AssistantPolicyDecision.allow,
        '已注册的实例进程操作',
      );
    }
    final command = action.command?.trim() ?? '';
    if (command.isEmpty ||
        command.length > 512 ||
        _controlCharacters.hasMatch(command)) {
      return const AssistantPolicyResult(
        AssistantPolicyDecision.deny,
        '命令为空、过长或包含控制字符',
      );
    }
    if (unrestricted) {
      return const AssistantPolicyResult(
        AssistantPolicyDecision.allow,
        'YOLO 模式：不限制命令内容',
      );
    }
    if (_hardDenied.hasMatch(command)) {
      return const AssistantPolicyResult(
        AssistantPolicyDecision.deny,
        '命令命中本地硬性安全规则',
      );
    }
    if (_privatePaths.hasMatch(command) || _parentTraversal.hasMatch(command)) {
      return const AssistantPolicyResult(
        AssistantPolicyDecision.deny,
        '命令尝试访问私密或宿主文件路径',
      );
    }
    if (_shellOperators.hasMatch(command)) {
      return const AssistantPolicyResult(
        AssistantPolicyDecision.manualOnly,
        '复合 Shell 命令只能由用户在终端中手动检查执行',
      );
    }
    final executable = command.split(RegExp(r'\s+')).first.toLowerCase();
    if (!_yoloExecutables.contains(executable)) {
      return const AssistantPolicyResult(
        AssistantPolicyDecision.manualOnly,
        '该命令未列入自动执行白名单',
      );
    }
    if (executable == 'git') {
      final operation = command.split(RegExp(r'\s+')).skip(1).firstOrNull;
      if (!const <String>{'status', 'branch', 'rev-parse'}
          .contains(operation)) {
        return const AssistantPolicyResult(
          AssistantPolicyDecision.manualOnly,
          'YOLO 只自动执行只读 Git 子命令',
        );
      }
    }
    if ((executable == 'python' || executable == 'python3') &&
        !RegExp(
          r'^python3?\s+(--?(version|help)|-[Vh])\b',
          caseSensitive: false,
        ).hasMatch(command)) {
      return const AssistantPolicyResult(
        AssistantPolicyDecision.manualOnly,
        'YOLO 不自动执行 Python 代码',
      );
    }
    if ((executable == 'pip' || executable == 'pip3') &&
        !RegExp(r'^pip3?\s+(list|show|check)\b', caseSensitive: false)
            .hasMatch(command)) {
      return const AssistantPolicyResult(
        AssistantPolicyDecision.manualOnly,
        'YOLO 不自动安装或卸载 Python 包',
      );
    }
    return const AssistantPolicyResult(
      AssistantPolicyDecision.allow,
      '只读命令，可由受控执行器运行',
    );
  }

  bool canFillTerminal(String command) =>
      command.isNotEmpty &&
      command.length <= 512 &&
      !_controlCharacters.hasMatch(command) &&
      !_hardDenied.hasMatch(command);
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
