import 'package:meta/meta.dart';

import '../../instance/domain/instance.dart';

/// 原生层授权的 rootfs 导航根类型。
enum RootfsFileScopeKind {
  instance('instance'),
  repository('repository');

  const RootfsFileScopeKind(this.wireName);

  final String wireName;
}

/// 一个命名的 rootfs 文件作用域。
///
/// 宿主机绝对路径不会离开 Android 原生层；这里只携带实例身份和可验证的
/// 容器路径声明。
@immutable
class RootfsFileScope {
  const RootfsFileScope({
    required this.kind,
    required this.instanceId,
    required this.instanceRootPath,
  });

  factory RootfsFileScope.forInstance(
    Instance instance, {
    RootfsFileScopeKind kind = RootfsFileScopeKind.repository,
  }) =>
      RootfsFileScope(
        kind: kind,
        instanceId: instance.id,
        instanceRootPath: instance.installDir,
      );

  final RootfsFileScopeKind kind;
  final String instanceId;
  final String instanceRootPath;

  String get id => '${kind.wireName}:$instanceId';

  String get displayName => switch (kind) {
        RootfsFileScopeKind.instance => '实例目录',
        RootfsFileScopeKind.repository => 'Bot 仓库',
      };

  RootfsFileScope withKind(RootfsFileScopeKind value) => RootfsFileScope(
        kind: value,
        instanceId: instanceId,
        instanceRootPath: instanceRootPath,
      );

  Map<String, Object> toChannelMap() => <String, Object>{
        'kind': kind.wireName,
        'instanceId': instanceId,
        'instanceRootPath': instanceRootPath,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RootfsFileScope &&
          kind == other.kind &&
          instanceId == other.instanceId &&
          instanceRootPath == other.instanceRootPath;

  @override
  int get hashCode => Object.hash(kind, instanceId, instanceRootPath);
}
