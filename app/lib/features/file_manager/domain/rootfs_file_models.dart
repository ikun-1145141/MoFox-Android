import 'package:meta/meta.dart';

import 'rootfs_file_scope.dart';
import 'rootfs_relative_path.dart';

enum RootfsFileKind {
  file('file'),
  directory('directory'),
  symlink('symlink'),
  other('other');

  const RootfsFileKind(this.wireName);

  final String wireName;

  static RootfsFileKind fromWireName(String value) {
    for (final kind in values) {
      if (kind.wireName == value) return kind;
    }
    throw FormatException('未知文件类型：$value');
  }
}

enum RootfsNewlineStyle {
  none('none'),
  lf('lf'),
  crlf('crlf'),
  mixed('mixed');

  const RootfsNewlineStyle(this.wireName);

  final String wireName;

  static RootfsNewlineStyle fromWireName(String value) {
    for (final style in values) {
      if (style.wireName == value) return style;
    }
    throw FormatException('未知换行格式：$value');
  }
}

enum RootfsWriteMode {
  mustExist('mustExist'),
  mustNotExist('mustNotExist');

  const RootfsWriteMode(this.wireName);

  final String wireName;
}

@immutable
class RootfsRevision {
  RootfsRevision(this.value) {
    if (!_revisionPattern.hasMatch(value)) {
      throw const FormatException('非法文件修订号');
    }
  }

  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is RootfsRevision && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

final RegExp _revisionPattern = RegExp(r'^sha256:[0-9a-f]{64}$');

class RootfsFileEntry {
  const RootfsFileEntry({
    required this.name,
    required this.relativePath,
    required this.kind,
    required this.modifiedAt,
    required this.isHidden,
    this.sizeBytes,
  });

  final String name;
  final RootfsRelativePath relativePath;
  final RootfsFileKind kind;
  final int? sizeBytes;
  final DateTime modifiedAt;
  final bool isHidden;

  bool get isDirectory => kind == RootfsFileKind.directory;
  bool get isToml =>
      kind == RootfsFileKind.file && name.toLowerCase().endsWith('.toml');
}

class RootfsDirectoryPage {
  const RootfsDirectoryPage({
    required this.entries,
    required this.directoryModifiedAt,
    this.nextCursor,
  });

  final List<RootfsFileEntry> entries;
  final String? nextCursor;
  final DateTime directoryModifiedAt;
}

class RootfsDocument {
  const RootfsDocument({
    required this.text,
    required this.hasUtf8Bom,
    required this.newlineStyle,
    required this.hasFinalNewline,
    required this.sizeBytes,
    required this.modifiedAt,
    required this.revision,
  });

  final String text;
  final bool hasUtf8Bom;
  final RootfsNewlineStyle newlineStyle;
  final bool hasFinalNewline;
  final int sizeBytes;
  final DateTime modifiedAt;
  final RootfsRevision revision;

  RootfsDocument copyWith({
    String? text,
    int? sizeBytes,
    DateTime? modifiedAt,
    RootfsRevision? revision,
  }) =>
      RootfsDocument(
        text: text ?? this.text,
        hasUtf8Bom: hasUtf8Bom,
        newlineStyle: newlineStyle,
        hasFinalNewline: hasFinalNewline,
        sizeBytes: sizeBytes ?? this.sizeBytes,
        modifiedAt: modifiedAt ?? this.modifiedAt,
        revision: revision ?? this.revision,
      );
}

class RootfsWriteResult {
  const RootfsWriteResult({
    required this.revision,
    required this.sizeBytes,
    required this.modifiedAt,
  });

  final RootfsRevision revision;
  final int sizeBytes;
  final DateTime modifiedAt;
}

class InstanceFilesRouteArgs {
  const InstanceFilesRouteArgs({
    required this.instanceName,
    required this.scope,
    this.initialRelativePath = const RootfsRelativePath.root(),
  });

  final String instanceName;
  final RootfsFileScope scope;
  final RootfsRelativePath initialRelativePath;
}

class TomlEditorRouteArgs {
  const TomlEditorRouteArgs({
    required this.scope,
    required this.relativePath,
    this.createMode = false,
  });

  final RootfsFileScope scope;
  final RootfsRelativePath relativePath;
  final bool createMode;
}
