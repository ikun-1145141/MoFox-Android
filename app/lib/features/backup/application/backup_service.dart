import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/platform_gateway.dart';
import '../../../core/runtime/runtime_bridge.dart';
import '../../../core/utils/app_logger.dart';
import '../../instance/domain/instance.dart';

/// 备份与导出服务。
///
/// 参考 PC 端启动器的两套体系：
/// 1. **一键打包导出** — config/ + napcat 登录态 + 最近日志 → ZIP → SAF
/// 2. **选择性导出** — 单独导出 core.toml / model.toml / napcat / 日志
/// 3. **从备份导入** — SAF 读取 ZIP → 解压恢复到实例目录
///
/// Android 端文件在 rootfs 内（proot Debian），通过 [RuntimeBridge] 读取。
class BackupService {
  BackupService(this._runtime, this._platform);

  final RuntimeBridge _runtime;
  final PlatformGateway _platform;

  /// 一键打包导出。
  ///
  /// 收集实例的 config/ 目录、napcat 配置、最近 N 天日志，
  /// 打包成 ZIP 后通过 SAF 让用户选保存位置。
  ///
  /// [instance] 要导出的实例。
  /// [includeLogs] 是否包含日志。
  /// [logDays] 日志保留天数（默认 7 天）。
  ///
  /// 返回导出的 content URI，用户取消返回 null。
  Future<String?> exportFullBackup({
    required Instance instance,
    bool includeLogs = true,
    int logDays = 7,
  }) async {
    appLogger.i('backup: exportFullBackup instance=${instance.id}');
    final repoPath = instance.repoPath;
    final archive = Archive();

    // 1. 收集 config/ 目录
    await _addDirToArchive(
      archive: archive,
      rootfsDirPath: '$repoPath/config',
      archivePrefix: 'config/',
    );

    // 2. 收集 napcat 配置
    await _addDirToArchive(
      archive: archive,
      rootfsDirPath: '/root/napcat/config',
      archivePrefix: 'napcat/config/',
    );

    // 3. 收集 napcat 登录态（token/session）
    await _addDirToArchive(
      archive: archive,
      rootfsDirPath:
          '/root/Napcat/opt/QQ/resources/app/app_launcher/napcat/config',
      archivePrefix: 'napcat/login_state/',
    );

    // 4. 收集日志
    if (includeLogs) {
      await _addDirToArchive(
        archive: archive,
        rootfsDirPath: '$repoPath/logs',
        archivePrefix: 'logs/',
      );
    }

    // 5. 写入 manifest.json
    final manifest = <String, Object?>{
      'version': 1,
      'type': 'mofox-android-backup',
      'instanceId': instance.id,
      'instanceName': instance.name,
      'botQq': instance.botQq,
      'createdAt': DateTime.now().toIso8601String(),
      'includeLogs': includeLogs,
    };
    archive.addFile(
      ArchiveFile.bytes(
        'manifest.json',
        Uint8List.fromList(utf8.encode(jsonEncode(manifest))),
      ),
    );

    // 6. 编码 ZIP
    final zipBytes = ZipEncoder().encode(archive);

    // 7. SAF 导出
    final fileName =
        'mofox-backup-${instance.name}-${DateTime.now().millisecondsSinceEpoch ~/ 1000}.zip';
    final uri = await _platform.exportToSaf(
      suggestedName: fileName,
      bytes: Uint8List.fromList(zipBytes),
    );
    appLogger.i('backup: exportFullBackup done uri=$uri');
    return uri;
  }

  /// 选择性导出单个文件或目录。
  ///
  /// [rootfsPath] rootfs 内的绝对路径。
  /// [exportName] 导出文件名。
  Future<String?> exportSingle({
    required String rootfsPath,
    required String exportName,
  }) async {
    appLogger.i('backup: exportSingle path=$rootfsPath name=$exportName');

    // 检查是文件还是目录
    final entries = await _runtime.listDir(rootfsPath);
    if (entries.isEmpty) {
      // 可能是文件
      final content = await _runtime.readFile(rootfsPath);
      if (content.isEmpty) {
        throw Exception('文件不存在或为空: $rootfsPath');
      }
      return _platform.exportToSaf(
        suggestedName: exportName,
        bytes: Uint8List.fromList(utf8.encode(content)),
      );
    }

    // 是目录，打包成 ZIP
    final archive = Archive();
    await _addDirToArchive(
      archive: archive,
      rootfsDirPath: rootfsPath,
      archivePrefix: '$exportName/',
    );
    final zipBytes = ZipEncoder().encode(archive);
    return _platform.exportToSaf(
      suggestedName: '$exportName.zip',
      bytes: Uint8List.fromList(zipBytes),
    );
  }

  /// 从备份导入。
  ///
  /// 通过 SAF 让用户选 ZIP 文件，解压后恢复到指定实例的目录。
  /// 返回导入的文件数量，用户取消返回 0。
  Future<int> importBackup({required Instance instance}) async {
    appLogger.i('backup: importBackup instance=${instance.id}');

    final bytes = await _platform.importFromSaf();
    if (bytes == null) {
      return 0;
    }

    final files = decodeBackup(bytes: bytes, instance: instance);
    if (files.isEmpty) {
      throw const FormatException('备份中没有可恢复的文件');
    }
    final count = await _runtime.writeFiles(files);
    if (count != files.length) {
      throw StateError('原生层只恢复了 $count/${files.length} 个文件');
    }

    appLogger.i('backup: importBackup done, $count files');
    return count;
  }

  /// 校验 Android 备份并映射到允许恢复的 rootfs 目标。
  ///
  /// 公开为静态方法，便于对 ZIP 路径穿越、格式版本和目标映射做单元测试。
  static List<RootfsFileWrite> decodeBackup({
    required Uint8List bytes,
    required Instance instance,
  }) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes, verify: true);
    } on Object catch (error) {
      throw FormatException('无法读取 ZIP 备份: $error');
    }

    final manifestFile = archive.files
        .where((file) => file.isFile && file.name == 'manifest.json')
        .firstOrNull;
    if (manifestFile == null) {
      throw const FormatException('不是有效的 MoFox Android 备份：缺少 manifest.json');
    }
    final manifest = _decodeManifest(_archiveBytes(manifestFile));
    if (manifest['type'] != 'mofox-android-backup' ||
        manifest['version'] != 1) {
      throw const FormatException('不支持的备份类型或版本');
    }

    final writes = <RootfsFileWrite>[];
    final destinations = <String>{};
    var totalBytes = 0;
    for (final file in archive.files) {
      if (!file.isFile || file.name == 'manifest.json') continue;
      final path = _normalizeArchivePath(file.name);
      final destination = _backupDestination(path, instance);
      if (destination == null) {
        appLogger.w('backup: 跳过未知路径 $path');
        continue;
      }
      if (!destinations.add(destination)) {
        throw FormatException('备份包含重复目标: $path');
      }
      final content = _archiveBytes(file);
      if (content.length > _maxImportFileBytes) {
        throw FormatException('单个备份文件过大: $path');
      }
      totalBytes += content.length;
      if (writes.length >= _maxImportFiles ||
          totalBytes > _maxImportTotalBytes) {
        throw const FormatException('备份文件数量或解压后体积超过上限');
      }
      writes.add(RootfsFileWrite(path: destination, bytes: content));
    }
    return writes;
  }

  /// 递归读取 rootfs 目录并添加到 archive。
  Future<void> _addDirToArchive({
    required Archive archive,
    required String rootfsDirPath,
    required String archivePrefix,
  }) async {
    try {
      final entries = await _runtime.listDir(rootfsDirPath);
      for (final entry in entries) {
        final archivePath = '$archivePrefix${entry.name}';
        if (entry.isDir) {
          await _addDirToArchive(
            archive: archive,
            rootfsDirPath: '$rootfsDirPath/${entry.name}',
            archivePrefix: '$archivePath/',
          );
        } else {
          final content =
              await _runtime.readFileBytes('$rootfsDirPath/${entry.name}');
          archive.addFile(
            ArchiveFile.bytes(
              archivePath,
              content,
            ),
          );
        }
      }
    } catch (e) {
      appLogger.w('backup: 读取目录 $rootfsDirPath 失败: $e');
    }
  }
}

Map<String, Object?> _decodeManifest(Uint8List bytes) {
  try {
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map<String, Object?>) {
      throw const FormatException('manifest.json 不是对象');
    }
    return value;
  } on FormatException {
    rethrow;
  } on Object catch (error) {
    throw FormatException('manifest.json 无效: $error');
  }
}

Uint8List _archiveBytes(ArchiveFile file) => file.content;

String _normalizeArchivePath(String rawPath) {
  final path = rawPath.replaceAll('\\', '/');
  final segments = path.split('/');
  if (path.startsWith('/') ||
      segments.any(
          (segment) => segment.isEmpty || segment == '.' || segment == '..')) {
    throw FormatException('备份包含不安全路径: $rawPath');
  }
  return segments.join('/');
}

String? _backupDestination(String path, Instance instance) {
  if (path.startsWith('config/')) {
    return '${instance.repoPath}/$path';
  }
  if (path.startsWith('logs/')) {
    return '${instance.repoPath}/$path';
  }
  if (path.startsWith('napcat/config/')) {
    return '/root/napcat/config/${path.substring('napcat/config/'.length)}';
  }
  if (path.startsWith('napcat/login_state/')) {
    return '/root/Napcat/opt/QQ/resources/app/app_launcher/napcat/config/'
        '${path.substring('napcat/login_state/'.length)}';
  }
  return null;
}

const int _maxImportFiles = 10000;
const int _maxImportFileBytes = 128 * 1024 * 1024;
const int _maxImportTotalBytes = 512 * 1024 * 1024;

final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService(
    ref.watch(runtimeBridgeProvider),
    ref.watch(platformGatewayProvider),
  );
});

/// 备份操作状态。
class BackupState {
  const BackupState({
    this.isExporting = false,
    this.isImporting = false,
    this.message,
    this.error,
  });

  final bool isExporting;
  final bool isImporting;
  final String? message;
  final String? error;

  BackupState copyWith({
    bool? isExporting,
    bool? isImporting,
    String? message,
    String? error,
  }) {
    return BackupState(
      isExporting: isExporting ?? this.isExporting,
      isImporting: isImporting ?? this.isImporting,
      message: message ?? this.message,
      error: error,
    );
  }
}

class BackupNotifier extends StateNotifier<BackupState> {
  BackupNotifier(this._service) : super(const BackupState());

  final BackupService _service;

  Future<String?> exportFullBackup({
    required Instance instance,
    bool includeLogs = true,
  }) async {
    state = state.copyWith(isExporting: true, message: '正在打包…', error: null);
    try {
      final uri = await _service.exportFullBackup(
        instance: instance,
        includeLogs: includeLogs,
      );
      state = state.copyWith(
        isExporting: false,
        message: uri != null ? '导出成功' : '已取消',
      );
      return uri;
    } catch (e) {
      state = state.copyWith(isExporting: false, error: e.toString());
      return null;
    }
  }

  Future<String?> exportSingle({
    required Instance instance,
    required String rootfsPath,
    required String exportName,
  }) async {
    state = state.copyWith(isExporting: true, message: '正在导出…', error: null);
    try {
      final uri = await _service.exportSingle(
        rootfsPath: rootfsPath,
        exportName: exportName,
      );
      state = state.copyWith(
        isExporting: false,
        message: uri != null ? '导出成功' : '已取消',
      );
      return uri;
    } catch (e) {
      state = state.copyWith(isExporting: false, error: e.toString());
      return null;
    }
  }

  Future<int> importBackup({required Instance instance}) async {
    state = state.copyWith(isImporting: true, message: '正在导入…', error: null);
    try {
      final count = await _service.importBackup(instance: instance);
      state = state.copyWith(
        isImporting: false,
        message: count > 0 ? '导入成功（$count 个文件）' : '已取消',
      );
      return count;
    } catch (e) {
      state = state.copyWith(isImporting: false, error: e.toString());
      return 0;
    }
  }
}

final backupNotifierProvider =
    StateNotifierProvider<BackupNotifier, BackupState>((ref) {
  return BackupNotifier(ref.watch(backupServiceProvider));
});
