import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mofox_android/features/backup/application/backup_service.dart';
import 'package:mofox_android/features/instance/domain/instance.dart';

void main() {
  final instance = Instance(
    id: 'test',
    name: '测试实例',
    botQq: '10001',
    botNickname: 'MoFox',
    ownerQq: '10000',
    wsPort: 8095,
    channel: 'main',
    installNapcat: true,
    installWebui: true,
    installDir: '/root/instances/test',
    createdAt: DateTime(2026),
  );

  test('maps supported backup paths to the selected instance', () {
    final bytes = _zip(<String, List<int>>{
      'config/core.toml': utf8.encode('enabled = true'),
      'logs/latest.log': utf8.encode('ok'),
      'napcat/config/onebot.json': utf8.encode('{}'),
      'napcat/login_state/session.bin': <int>[0, 255, 1],
    });

    final writes = BackupService.decodeBackup(bytes: bytes, instance: instance);

    expect(
      writes.map((write) => write.path),
      <String>[
        '/root/instances/test/Neo-MoFox/config/core.toml',
        '/root/instances/test/Neo-MoFox/logs/latest.log',
        '/root/napcat/config/onebot.json',
        '/root/Napcat/opt/QQ/resources/app/app_launcher/napcat/config/session.bin',
      ],
    );
    expect(writes.last.bytes, Uint8List.fromList(<int>[0, 255, 1]));
  });

  test('rejects path traversal entries', () {
    final bytes = _zip(<String, List<int>>{
      'config/../../etc/passwd': utf8.encode('bad'),
    });

    expect(
      () => BackupService.decodeBackup(bytes: bytes, instance: instance),
      throwsFormatException,
    );
  });

  test('rejects archives without a supported manifest', () {
    final archive = Archive()
      ..addFile(ArchiveFile.bytes('config/core.toml', utf8.encode('x')));
    final bytes = Uint8List.fromList(ZipEncoder().encode(archive));

    expect(
      () => BackupService.decodeBackup(bytes: bytes, instance: instance),
      throwsFormatException,
    );
  });
}

Uint8List _zip(Map<String, List<int>> files) {
  final archive = Archive()
    ..addFile(
      ArchiveFile.bytes(
        'manifest.json',
        utf8.encode(
          jsonEncode(<String, Object?>{
            'version': 1,
            'type': 'mofox-android-backup',
          }),
        ),
      ),
    );
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile.bytes(entry.key, entry.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
