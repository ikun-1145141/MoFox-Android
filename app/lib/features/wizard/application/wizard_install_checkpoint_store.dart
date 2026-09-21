import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/wizard_step.dart';

class WizardInstallCheckpoint {
  const WizardInstallCheckpoint({
    required this.instanceId,
    required this.installDir,
    required this.draft,
    required this.taskStatus,
  });

  final String instanceId;
  final String installDir;
  final InstanceDraft draft;
  final Map<InstallTask, InstallTaskStatus> taskStatus;

  Map<String, Object?> toJson() => <String, Object?>{
        'version': 1,
        'instanceId': instanceId,
        'installDir': installDir,
        'draft': <String, Object?>{
          'eulaAccepted': draft.eulaAccepted,
          'mirrorId': draft.mirrorId,
          'name': draft.name,
          'botQq': draft.botQq,
          'botNickname': draft.botNickname,
          'ownerQq': draft.ownerQq,
          'apiKey': draft.apiKey,
          'wsPort': draft.wsPort,
          'channel': draft.channel,
          'webuiApiKey': draft.webuiApiKey,
          'installWebui': draft.installWebui,
        },
        'taskStatus': <String, String>{
          for (final entry in taskStatus.entries)
            entry.key.name: entry.value.name,
        },
      };

  static WizardInstallCheckpoint fromJson(Map<String, Object?> json) {
    if (json['version'] != 1) {
      throw const FormatException('不支持的安装断点版本');
    }
    final rawDraft = json['draft'];
    final rawStatuses = json['taskStatus'];
    if (rawDraft is! Map<String, dynamic> ||
        rawStatuses is! Map<String, dynamic>) {
      throw const FormatException('安装断点结构无效');
    }
    final draft = InstanceDraft(
      eulaAccepted: rawDraft['eulaAccepted'] == true,
      mirrorId: _requiredString(rawDraft, 'mirrorId'),
      name: _requiredString(rawDraft, 'name'),
      botQq: _requiredString(rawDraft, 'botQq'),
      botNickname: _requiredString(rawDraft, 'botNickname'),
      ownerQq: _requiredString(rawDraft, 'ownerQq'),
      apiKey: _requiredString(rawDraft, 'apiKey'),
      wsPort: _requiredInt(rawDraft, 'wsPort'),
      channel: _requiredString(rawDraft, 'channel'),
      webuiApiKey: _requiredString(rawDraft, 'webuiApiKey'),
      installWebui: rawDraft['installWebui'] == true,
    );
    return WizardInstallCheckpoint(
      instanceId: _requiredString(json, 'instanceId'),
      installDir: _requiredString(json, 'installDir'),
      draft: draft,
      taskStatus: <InstallTask, InstallTaskStatus>{
        for (final task in InstallTask.values)
          task: _statusFromName(rawStatuses[task.name]?.toString()),
      },
    );
  }
}

abstract interface class WizardInstallCheckpointStore {
  Future<WizardInstallCheckpoint?> read(String instanceId);
  Future<void> write(WizardInstallCheckpoint checkpoint);
  Future<void> delete(String instanceId);
}

class SecureWizardInstallCheckpointStore
    implements WizardInstallCheckpointStore {
  const SecureWizardInstallCheckpointStore();

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  @override
  Future<WizardInstallCheckpoint?> read(String instanceId) async {
    final raw = await _storage.read(key: _key(instanceId));
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('安装断点不是 JSON 对象');
    }
    return WizardInstallCheckpoint.fromJson(decoded);
  }

  @override
  Future<void> write(WizardInstallCheckpoint checkpoint) => _storage.write(
        key: _key(checkpoint.instanceId),
        value: jsonEncode(checkpoint.toJson()),
      );

  @override
  Future<void> delete(String instanceId) =>
      _storage.delete(key: _key(instanceId));

  static String _key(String instanceId) =>
      'wizard_install_checkpoint_v1_$instanceId';
}

final wizardInstallCheckpointStoreProvider =
    Provider<WizardInstallCheckpointStore>(
  (_) => const SecureWizardInstallCheckpointStore(),
);

String _requiredString(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is String) return value;
  throw FormatException('安装断点缺少 $key');
}

int _requiredInt(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  throw FormatException('安装断点缺少 $key');
}

InstallTaskStatus _statusFromName(String? name) {
  for (final status in InstallTaskStatus.values) {
    if (status.name == name) return status;
  }
  return InstallTaskStatus.pending;
}
