/// Flutter 层稳定的 rootfs 文件错误码。
enum RootfsFileErrorCode {
  scopeNotFound('SCOPE_NOT_FOUND'),
  rootfsNotReady('ROOTFS_NOT_READY'),
  invalidPath('INVALID_PATH'),
  pathEscape('PATH_ESCAPE'),
  symlinkNotAllowed('SYMLINK_NOT_ALLOWED'),
  rootOperationForbidden('ROOT_OPERATION_FORBIDDEN'),
  notFound('NOT_FOUND'),
  alreadyExists('ALREADY_EXISTS'),
  notDirectory('NOT_DIRECTORY'),
  isDirectory('IS_DIRECTORY'),
  unsupportedFileType('UNSUPPORTED_FILE_TYPE'),
  permissionDenied('PERMISSION_DENIED'),
  readOnlyScope('READ_ONLY_SCOPE'),
  fileTooLarge('FILE_TOO_LARGE'),
  invalidUtf8('INVALID_UTF8'),
  conflict('CONFLICT'),
  directoryNotEmpty('DIRECTORY_NOT_EMPTY'),
  staleListing('STALE_LISTING'),
  busy('BUSY'),
  ioError('IO_ERROR'),
  malformedResponse('MALFORMED_RESPONSE');

  const RootfsFileErrorCode(this.wireName);

  final String wireName;

  static RootfsFileErrorCode fromWireName(String value) {
    for (final code in values) {
      if (code.wireName == value) return code;
    }
    return RootfsFileErrorCode.ioError;
  }
}

class RootfsFileException implements Exception {
  const RootfsFileException({
    required this.code,
    required this.message,
    this.operation,
    this.scopeId,
    this.relativePath,
    this.retryable = false,
    this.currentRevision,
    this.requestId,
  });

  final RootfsFileErrorCode code;
  final String message;
  final String? operation;
  final String? scopeId;
  final String? relativePath;
  final bool retryable;
  final String? currentRevision;
  final String? requestId;

  @override
  String toString() => message;
}
