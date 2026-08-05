package com.mofox.android.runtime

/** A named, app-authorized root inside the proot rootfs. */
internal enum class RootfsScopeKind(val wireName: String) {
    INSTANCE("instance"),
    REPOSITORY("repository");

    companion object {
        fun fromWireName(value: String): RootfsScopeKind =
            entries.firstOrNull { it.wireName == value }
                ?: throw RuntimeFileException(
                    code = RuntimeFileErrorCode.INVALID_PATH,
                    operation = "decodeScope",
                    message = "Unsupported file scope",
                )
    }
}

internal data class RootfsScope(
    val kind: RootfsScopeKind,
    val instanceId: String,
    val instanceRootPath: String? = null,
) {
    val id: String get() = "${kind.wireName}:$instanceId"
}

internal enum class RootfsFileKind(val wireName: String) {
    FILE("file"),
    DIRECTORY("directory"),
    SYMLINK("symlink"),
    OTHER("other"),
}

internal enum class RootfsWriteMode(val wireName: String) {
    MUST_EXIST("mustExist"),
    MUST_NOT_EXIST("mustNotExist");

    companion object {
        fun fromWireName(value: String): RootfsWriteMode =
            entries.firstOrNull { it.wireName == value }
                ?: throw RuntimeFileException(
                    code = RuntimeFileErrorCode.INVALID_PATH,
                    operation = "decodeWriteMode",
                    message = "Unsupported write mode",
                )
    }
}

internal data class RuntimeFileEntry(
    val name: String,
    val pathSegments: List<String>,
    val kind: RootfsFileKind,
    val sizeBytes: Long?,
    val modifiedAtMillis: Long,
) {
    fun toMap(): Map<String, Any?> =
        mapOf(
            "name" to name,
            "pathSegments" to pathSegments,
            "kind" to kind.wireName,
            "sizeBytes" to sizeBytes,
            "modifiedAt" to modifiedAtMillis,
            "isHidden" to name.startsWith('.'),
        )
}

internal data class RuntimeDirectoryPage(
    val entries: List<RuntimeFileEntry>,
    val nextCursor: String?,
    val directoryModifiedAtMillis: Long,
) {
    fun toMap(): Map<String, Any?> =
        mapOf(
            "entries" to entries.map(RuntimeFileEntry::toMap),
            "nextCursor" to nextCursor,
            "directoryModifiedAt" to directoryModifiedAtMillis,
        )
}

internal enum class RuntimeNewlineStyle(val wireName: String) {
    NONE("none"),
    LF("lf"),
    CRLF("crlf"),
    MIXED("mixed"),
}

internal data class RuntimeTextDocument(
    val text: String,
    val hasUtf8Bom: Boolean,
    val newlineStyle: RuntimeNewlineStyle,
    val hasFinalNewline: Boolean,
    val sizeBytes: Long,
    val modifiedAtMillis: Long,
    val revision: String,
) {
    fun toMap(): Map<String, Any?> =
        mapOf(
            "text" to text,
            "encoding" to "utf-8",
            "hasUtf8Bom" to hasUtf8Bom,
            "newlineStyle" to newlineStyle.wireName,
            "hasFinalNewline" to hasFinalNewline,
            "sizeBytes" to sizeBytes,
            "modifiedAt" to modifiedAtMillis,
            "revision" to revision,
        )
}

internal data class RuntimeWriteResult(
    val revision: String,
    val sizeBytes: Long,
    val modifiedAtMillis: Long,
) {
    fun toMap(): Map<String, Any?> =
        mapOf(
            "revision" to revision,
            "sizeBytes" to sizeBytes,
            "modifiedAt" to modifiedAtMillis,
        )
}

internal enum class RuntimeFileErrorCode {
    SCOPE_NOT_FOUND,
    ROOTFS_NOT_READY,
    INVALID_PATH,
    PATH_ESCAPE,
    SYMLINK_NOT_ALLOWED,
    ROOT_OPERATION_FORBIDDEN,
    NOT_FOUND,
    ALREADY_EXISTS,
    NOT_DIRECTORY,
    IS_DIRECTORY,
    UNSUPPORTED_FILE_TYPE,
    PERMISSION_DENIED,
    READ_ONLY_SCOPE,
    FILE_TOO_LARGE,
    INVALID_UTF8,
    CONFLICT,
    DIRECTORY_NOT_EMPTY,
    STALE_LISTING,
    BUSY,
    IO_ERROR,
}

internal class RuntimeFileException(
    val code: RuntimeFileErrorCode,
    val operation: String,
    override val message: String,
    val scopeId: String? = null,
    val relativePath: String? = null,
    val retryable: Boolean = false,
    val currentRevision: String? = null,
    cause: Throwable? = null,
) : RuntimeException(message, cause) {
    fun details(requestId: String? = null): Map<String, Any?> =
        mapOf(
            "requestId" to requestId,
            "operation" to operation,
            "scopeId" to scopeId,
            "relativePath" to relativePath,
            "retryable" to retryable,
            "currentRevision" to currentRevision,
        )
}
