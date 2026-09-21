import 'wizard_step.dart';

abstract final class WizardValidation {
  static String? instanceName(
    String value, {
    Iterable<String> existingNames = const <String>[],
  }) {
    final name = value.trim();
    if (name.isEmpty) return '请输入实例名称';
    if (name.length > 32) return '实例名称不能超过 32 个字符';
    if (RegExp(r'[\x00-\x1f/\\]').hasMatch(name)) {
      return '实例名称不能包含换行或路径分隔符';
    }
    final normalized = name.toLowerCase();
    if (existingNames.any((item) => item.trim().toLowerCase() == normalized)) {
      return '已有同名实例';
    }
    return null;
  }

  static String? qq(String value, {required String label}) {
    final qq = value.trim();
    if (qq.isEmpty) return '请输入$label';
    if (!RegExp(r'^\d{5,12}$').hasMatch(qq)) {
      return '$label应为 5–12 位数字';
    }
    return null;
  }

  static String? apiKey(String value) {
    final key = value.trim();
    if (key.isEmpty) return '请输入 API Key';
    if (key.length < 16) return 'API Key 格式过短，请检查是否完整';
    if (key.contains(RegExp(r'\s'))) return 'API Key 不能包含空格';
    return null;
  }

  static String? port(int value) {
    if (value < 1 || value > 65535) return '端口必须在 1–65535 之间';
    return null;
  }

  static String? webuiKey(String value, {required bool enabled}) {
    if (!enabled) return null;
    final key = value.trim();
    if (key.isEmpty) return '请设置 WebUI 访问密钥';
    if (key.length < 12) return '建议使用至少 12 位的 WebUI 密钥';
    if (key.contains(RegExp(r'\s'))) return 'WebUI 密钥不能包含空格';
    return null;
  }

  static bool draftIsValid(
    InstanceDraft draft, {
    Iterable<String> existingNames = const <String>[],
  }) =>
      instanceName(draft.name, existingNames: existingNames) == null &&
      qq(draft.botQq, label: 'Bot QQ') == null &&
      qq(draft.ownerQq, label: '主人 QQ') == null &&
      apiKey(draft.apiKey) == null &&
      port(draft.wsPort) == null &&
      webuiKey(draft.webuiApiKey, enabled: draft.installWebui) == null;
}
