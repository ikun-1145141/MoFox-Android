import 'dart:convert';

/// 单个 MoFox Bot 实例的元数据。
///
/// Wizard 完成后会写一条 [Instance] 到 [InstanceRepository]，
/// dashboard 据此渲染卡片列表。运行时状态（启动/停止/日志）不在这里，
/// 由后续的 `RuntimeBridge` provider 单独维护。
class Instance {
  const Instance({
    required this.id,
    required this.name,
    required this.botQq,
    required this.botNickname,
    required this.ownerQq,
    required this.wsPort,
    required this.channel,
    required this.installNapcat,
    required this.installWebui,
    required this.installDir,
    required this.createdAt,
    this.installStatus = InstanceInstallStatus.installed,
    this.lastInstallTask,
    this.installError,
  });

  final String id;
  final String name;
  final String botQq;
  final String botNickname;
  final String ownerQq;
  final int wsPort;
  final String channel; // 'main' | 'dev'
  final bool installNapcat;
  final bool installWebui;

  /// 此实例在 rootfs 内的安装根目录，例如 `/root/instances/inst-1717000000000`。
  ///
  /// NapCat 是全局共享的（`/root/napcat`），所以这里只描述 bot 自己的目录。
  final String installDir;
  final DateTime createdAt;

  /// 安装状态。未完成实例会保留在主界面，供后续续装。
  final InstanceInstallStatus installStatus;

  /// 最近失败或中断时所在的安装任务名。
  final String? lastInstallTask;

  /// 最近一次安装错误信息。
  final String? installError;

  /// Bot 仓库路径（`<installDir>/Neo-MoFox`）。
  String get repoPath => '$installDir/Neo-MoFox';

  Instance copyWith({
    String? name,
    String? botQq,
    String? botNickname,
    String? ownerQq,
    int? wsPort,
    String? channel,
    bool? installNapcat,
    bool? installWebui,
    String? installDir,
    InstanceInstallStatus? installStatus,
    Object? lastInstallTask = _sentinel,
    Object? installError = _sentinel,
  }) =>
      Instance(
        id: id,
        name: name ?? this.name,
        botQq: botQq ?? this.botQq,
        botNickname: botNickname ?? this.botNickname,
        ownerQq: ownerQq ?? this.ownerQq,
        wsPort: wsPort ?? this.wsPort,
        channel: channel ?? this.channel,
        installNapcat: installNapcat ?? this.installNapcat,
        installWebui: installWebui ?? this.installWebui,
        installDir: installDir ?? this.installDir,
        createdAt: createdAt,
        installStatus: installStatus ?? this.installStatus,
        lastInstallTask: identical(lastInstallTask, _sentinel)
            ? this.lastInstallTask
            : lastInstallTask as String?,
        installError: identical(installError, _sentinel)
            ? this.installError
            : installError as String?,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'botQq': botQq,
        'botNickname': botNickname,
        'ownerQq': ownerQq,
        'wsPort': wsPort,
        'channel': channel,
        'installNapcat': installNapcat,
        'installWebui': installWebui,
        'installDir': installDir,
        'createdAt': createdAt.toIso8601String(),
        'installStatus': installStatus.name,
        'lastInstallTask': lastInstallTask,
        'installError': installError,
      };

  static Instance fromJson(Map<String, Object?> json) => Instance(
        id: json['id']! as String,
        name: json['name']! as String,
        botQq: json['botQq']! as String,
        botNickname: json['botNickname']! as String,
        ownerQq: json['ownerQq']! as String,
        wsPort: (json['wsPort']! as num).toInt(),
        channel: json['channel']! as String,
        installNapcat: json['installNapcat']! as bool,
        installWebui: json['installWebui']! as bool,
        installDir: json['installDir'] as String? ??
            '/root/instances/${json['id']}',
        createdAt: DateTime.parse(json['createdAt']! as String),
        installStatus: InstanceInstallStatusX.fromName(
          json['installStatus'] as String?,
        ),
        lastInstallTask: json['lastInstallTask'] as String?,
        installError: json['installError'] as String?,
      );

  String encode() => jsonEncode(toJson());
  static Instance decode(String raw) =>
      fromJson(jsonDecode(raw) as Map<String, Object?>);
}

const Object _sentinel = Object();

enum InstanceInstallStatus { installing, failed, installed }

extension InstanceInstallStatusX on InstanceInstallStatus {
  static InstanceInstallStatus fromName(String? name) {
    for (final status in InstanceInstallStatus.values) {
      if (status.name == name) return status;
    }
    return InstanceInstallStatus.installed;
  }
}
