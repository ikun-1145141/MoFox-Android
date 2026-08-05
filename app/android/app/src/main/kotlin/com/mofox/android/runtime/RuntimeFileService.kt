package com.mofox.android.runtime

import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import android.system.StructStat
import android.util.Base64
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.util.Locale
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

internal class RuntimeFileService(private val resolver: RootfsPathResolver) {
    // Mutation locks intentionally live for the service lifetime. Removing a lock while
    // another thread is waiting on it can create two lock objects for the same scope.
    // A scope-wide lock also gives rename/delete/create predictable ordering with writes.
    private val mutationLocks = ConcurrentHashMap<String, Any>()

    fun listDirectory(
        scope: RootfsScope,
        pathSegments: List<String>,
        limit: Int,
        cursor: String?,
    ): RuntimeDirectoryPage =
        runFileOperation("listDirectory", scope, pathSegments) {
            val safeLimit = limit.coerceIn(1, MAX_DIRECTORY_PAGE_SIZE)
            val resolved = resolver.resolve(scope, pathSegments, "listDirectory")
            val directoryStat = resolved.stat ?: error("Resolved directory has no stat")
            requireDirectory(directoryStat, "listDirectory", scope, pathSegments)
            requireNotSymlink(directoryStat, "listDirectory", scope, pathSegments)

            val entries = resolved.target.listFiles()
                ?: throw RuntimeFileException(
                    code = RuntimeFileErrorCode.PERMISSION_DENIED,
                    operation = "listDirectory",
                    message = "Directory cannot be listed",
                    scopeId = scope.id,
                    relativePath = pathSegments.joinToString("/"),
                )
            val sorted = entries.map { child ->
                val childStat = Os.lstat(child.absolutePath)
                RuntimeFileEntry(
                    name = child.name,
                    pathSegments = pathSegments + child.name,
                    kind = kindOf(childStat),
                    sizeBytes = if (OsConstants.S_ISREG(childStat.st_mode)) childStat.st_size else null,
                    modifiedAtMillis = childStat.modifiedAtMillis(),
                )
            }.sortedWith(
                compareBy<RuntimeFileEntry>(
                    { if (it.kind == RootfsFileKind.DIRECTORY) 0 else 1 },
                    { it.name.lowercase(Locale.ROOT) },
                    { it.name },
                ),
            )

            val startIndex = cursor?.let { rawCursor ->
                val decoded = decodeCursor(rawCursor, scope, pathSegments)
                val index = sorted.indexOfFirst {
                    it.kind.wireName == decoded.first && it.name == decoded.second
                }
                if (index < 0) {
                    throw RuntimeFileException(
                        code = RuntimeFileErrorCode.STALE_LISTING,
                        operation = "listDirectory",
                        message = "Directory changed while paging",
                        scopeId = scope.id,
                        relativePath = pathSegments.joinToString("/"),
                        retryable = true,
                    )
                }
                index + 1
            } ?: 0

            val page = sorted.drop(startIndex).take(safeLimit)
            val nextCursor = if (startIndex + page.size < sorted.size) {
                page.lastOrNull()?.let(::encodeCursor)
            } else {
                null
            }
            RuntimeDirectoryPage(
                entries = page,
                nextCursor = nextCursor,
                directoryModifiedAtMillis = directoryStat.modifiedAtMillis(),
            )
        }

    fun statPath(scope: RootfsScope, pathSegments: List<String>): RuntimeFileEntry =
        runFileOperation("statPath", scope, pathSegments) {
            val resolved = resolver.resolve(scope, pathSegments, "statPath")
            val stat = resolved.stat ?: error("Resolved path has no stat")
            RuntimeFileEntry(
                name = pathSegments.lastOrNull() ?: scope.id,
                pathSegments = pathSegments.toList(),
                kind = kindOf(stat),
                sizeBytes = if (OsConstants.S_ISREG(stat.st_mode)) stat.st_size else null,
                modifiedAtMillis = stat.modifiedAtMillis(),
            )
        }

    fun readTextDocument(
        scope: RootfsScope,
        pathSegments: List<String>,
        maxBytes: Int,
    ): RuntimeTextDocument =
        runFileOperation("readTextDocument", scope, pathSegments) {
            val safeMaxBytes = maxBytes.coerceIn(1, MAX_TEXT_FILE_BYTES)
            val resolved = resolver.resolve(scope, pathSegments, "readTextDocument")
            val stat = resolved.stat ?: error("Resolved path has no stat")
            requireRegularFile(stat, "readTextDocument", scope, pathSegments)
            requireNotSymlink(stat, "readTextDocument", scope, pathSegments)
            if (stat.st_size > safeMaxBytes) {
                throw RuntimeFileException(
                    code = RuntimeFileErrorCode.FILE_TOO_LARGE,
                    operation = "readTextDocument",
                    message = "Text file exceeds the configured limit",
                    scopeId = scope.id,
                    relativePath = pathSegments.joinToString("/"),
                )
            }

            val bytes = readFileNoFollow(resolved.target, safeMaxBytes)
            decodeDocument(bytes, stat)
        }

    fun writeTextDocument(
        scope: RootfsScope,
        pathSegments: List<String>,
        text: String,
        hasUtf8Bom: Boolean,
        writeMode: RootfsWriteMode,
        expectedRevision: String?,
    ): RuntimeWriteResult =
        runFileOperation("writeTextDocument", scope, pathSegments) {
            if ('\u0000' in text) {
                throw RuntimeFileException(
                    code = RuntimeFileErrorCode.INVALID_UTF8,
                    operation = "writeTextDocument",
                    message = "Text documents cannot contain NUL bytes",
                    scopeId = scope.id,
                    relativePath = pathSegments.joinToString("/"),
                )
            }
            val body = text.toByteArray(Charsets.UTF_8)
            val bytes = if (hasUtf8Bom) UTF8_BOM + body else body
            if (bytes.size > MAX_TEXT_FILE_BYTES) {
                throw RuntimeFileException(
                    code = RuntimeFileErrorCode.FILE_TOO_LARGE,
                    operation = "writeTextDocument",
                    message = "Text file exceeds the configured limit",
                    scopeId = scope.id,
                    relativePath = pathSegments.joinToString("/"),
                )
            }

            withMutationLock(scope) {
                writeTextDocumentLocked(
                    scope = scope,
                    pathSegments = pathSegments,
                    bytes = bytes,
                    writeMode = writeMode,
                    expectedRevision = expectedRevision,
                )
            }
        }

    fun createDirectory(scope: RootfsScope, parentPathSegments: List<String>, name: String) {
        runFileOperation("createDirectory", scope, parentPathSegments + name) {
            withMutationLock(scope) {
                resolver.validateName(name, "createDirectory", scope)
                val parent = resolver.resolve(scope, parentPathSegments, "createDirectory")
                val parentStat = parent.stat ?: error("Resolved parent has no stat")
                requireDirectory(parentStat, "createDirectory", scope, parentPathSegments)
                requireNotSymlink(parentStat, "createDirectory", scope, parentPathSegments)

                val target = File(parent.target, name)
                if (lstatOrNull(target) != null) {
                    throw RuntimeFileException(
                        code = RuntimeFileErrorCode.ALREADY_EXISTS,
                        operation = "createDirectory",
                        message = "A file with that name already exists",
                        scopeId = scope.id,
                        relativePath = (parentPathSegments + name).joinToString("/"),
                    )
                }
                Os.mkdir(target.absolutePath, DEFAULT_DIRECTORY_MODE)
                fsyncDirectory(parent.target)
            }
        }
    }

    fun renameEntry(scope: RootfsScope, pathSegments: List<String>, newName: String) {
        runFileOperation("renameEntry", scope, pathSegments) {
            withMutationLock(scope) {
                resolver.validateName(newName, "renameEntry", scope)
                val source = resolver.resolve(scope, pathSegments, "renameEntry")
                resolver.requireMutableTarget(source, "renameEntry")
                resolver.ensureParentChain(source, "renameEntry")
                val parent = source.target.parentFile ?: error("Target has no parent")
                val target = File(parent, newName)
                if (lstatOrNull(target) != null) {
                    throw RuntimeFileException(
                        code = RuntimeFileErrorCode.ALREADY_EXISTS,
                        operation = "renameEntry",
                        message = "A file with that name already exists",
                        scopeId = scope.id,
                        relativePath = (pathSegments.dropLast(1) + newName).joinToString("/"),
                    )
                }
                Os.rename(source.target.absolutePath, target.absolutePath)
                fsyncDirectory(parent)
            }
        }
    }

    fun deleteEntry(scope: RootfsScope, pathSegments: List<String>, recursive: Boolean) {
        runFileOperation("deleteEntry", scope, pathSegments) {
            withMutationLock(scope) {
                val resolved = resolver.resolve(scope, pathSegments, "deleteEntry")
                resolver.requireMutableTarget(resolved, "deleteEntry")
                resolver.ensureParentChain(resolved, "deleteEntry")
                val parent = resolved.target.parentFile ?: error("Target has no parent")
                deleteResolved(
                    resolved.target,
                    resolved.stat ?: error("Resolved path has no stat"),
                    recursive,
                )
                fsyncDirectory(parent)
            }
        }
    }

    private fun writeTextDocumentLocked(
        scope: RootfsScope,
        pathSegments: List<String>,
        bytes: ByteArray,
        writeMode: RootfsWriteMode,
        expectedRevision: String?,
    ): RuntimeWriteResult {
        val operation = "writeTextDocument"
        val resolved = resolver.resolve(
            scope = scope,
            pathSegments = pathSegments,
            operation = operation,
            allowMissingLeaf = writeMode == RootfsWriteMode.MUST_NOT_EXIST,
        )
        resolver.requireMutableTarget(resolved, operation)
        resolver.ensureParentChain(resolved, operation)
        val existingStat = lstatOrNull(resolved.target)

        when (writeMode) {
            RootfsWriteMode.MUST_EXIST -> {
                val stat = existingStat
                    ?: throw RuntimeFileException(
                        code = RuntimeFileErrorCode.NOT_FOUND,
                        operation = operation,
                        message = "File no longer exists",
                        scopeId = scope.id,
                        relativePath = pathSegments.joinToString("/"),
                    )
                requireRegularFile(stat, operation, scope, pathSegments)
                requireNotSymlink(stat, operation, scope, pathSegments)
                if (expectedRevision.isNullOrBlank()) {
                    throw RuntimeFileException(
                        code = RuntimeFileErrorCode.INVALID_PATH,
                        operation = operation,
                        message = "Expected revision is required",
                        scopeId = scope.id,
                        relativePath = pathSegments.joinToString("/"),
                    )
                }
                val currentBytes = readFileNoFollow(resolved.target, MAX_TEXT_FILE_BYTES)
                val currentRevision = revisionOf(currentBytes)
                if (currentRevision != expectedRevision) {
                    throw RuntimeFileException(
                        code = RuntimeFileErrorCode.CONFLICT,
                        operation = operation,
                        message = "File changed outside the editor",
                        scopeId = scope.id,
                        relativePath = pathSegments.joinToString("/"),
                        currentRevision = currentRevision,
                    )
                }
                atomicReplace(
                    resolved = resolved,
                    bytes = bytes,
                    mode = stat.st_mode and PERMISSION_BITS_MASK,
                    expectedRevision = expectedRevision,
                )
            }
            RootfsWriteMode.MUST_NOT_EXIST -> {
                if (existingStat != null) {
                    throw RuntimeFileException(
                        code = RuntimeFileErrorCode.ALREADY_EXISTS,
                        operation = operation,
                        message = "A file with that name already exists",
                        scopeId = scope.id,
                        relativePath = pathSegments.joinToString("/"),
                    )
                }
                createExclusive(resolved, bytes)
            }
        }

        val stat = resolver.restat(resolved, operation)
        return RuntimeWriteResult(
            revision = revisionOf(bytes),
            sizeBytes = bytes.size.toLong(),
            modifiedAtMillis = stat.modifiedAtMillis(),
        )
    }

    private fun atomicReplace(
        resolved: ResolvedRootfsPath,
        bytes: ByteArray,
        mode: Int,
        expectedRevision: String,
    ) {
        val parent = resolved.target.parentFile ?: error("Target has no parent")
        val temp = File(parent, ".${resolved.target.name}.mofox-${UUID.randomUUID()}.tmp")
        try {
            writeExclusive(temp, bytes, if (mode == 0) DEFAULT_FILE_MODE else mode)
            resolver.ensureParentChain(resolved, "writeTextDocument")
            val latest = resolver.restat(resolved, "writeTextDocument")
            requireRegularFile(
                latest,
                "writeTextDocument",
                resolved.scope,
                resolved.pathSegments,
            )
            requireNotSymlink(
                latest,
                "writeTextDocument",
                resolved.scope,
                resolved.pathSegments,
            )
            val latestRevision = revisionOf(readFileNoFollow(resolved.target, MAX_TEXT_FILE_BYTES))
            if (latestRevision != expectedRevision) {
                throw RuntimeFileException(
                    code = RuntimeFileErrorCode.CONFLICT,
                    operation = "writeTextDocument",
                    message = "File changed outside the editor",
                    scopeId = resolved.scope.id,
                    relativePath = resolved.pathSegments.joinToString("/"),
                    currentRevision = latestRevision,
                )
            }
            Os.rename(temp.absolutePath, resolved.target.absolutePath)
            fsyncDirectory(parent)
        } finally {
            removeIfPresent(temp)
        }
    }

    private fun createExclusive(resolved: ResolvedRootfsPath, bytes: ByteArray) {
        resolver.ensureParentChain(resolved, "writeTextDocument")
        writeExclusive(resolved.target, bytes, DEFAULT_FILE_MODE)
        resolved.target.parentFile?.let(::fsyncDirectory)
    }

    private fun writeExclusive(file: File, bytes: ByteArray, mode: Int) {
        val descriptor = Os.open(
            file.absolutePath,
            OsConstants.O_WRONLY or
                OsConstants.O_CREAT or
                OsConstants.O_EXCL or
                OsConstants.O_NOFOLLOW,
            mode,
        )
        try {
            Os.fchmod(descriptor, mode)
            var offset = 0
            while (offset < bytes.size) {
                offset += Os.write(descriptor, bytes, offset, bytes.size - offset)
            }
            Os.fsync(descriptor)
        } finally {
            Os.close(descriptor)
        }
    }

    private fun readFileNoFollow(file: File, maxBytes: Int): ByteArray {
        val descriptor = Os.open(
            file.absolutePath,
            OsConstants.O_RDONLY or OsConstants.O_NOFOLLOW,
            0,
        )
        try {
            val output = ByteArrayOutputStream()
            val buffer = ByteArray(16 * 1024)
            while (true) {
                val count = Os.read(descriptor, buffer, 0, buffer.size)
                if (count <= 0) break
                if (output.size() + count > maxBytes) {
                    throw RuntimeFileException(
                        code = RuntimeFileErrorCode.FILE_TOO_LARGE,
                        operation = "readTextDocument",
                        message = "Text file exceeds the configured limit",
                    )
                }
                output.write(buffer, 0, count)
            }
            return output.toByteArray()
        } finally {
            Os.close(descriptor)
        }
    }

    private fun decodeDocument(bytes: ByteArray, stat: StructStat): RuntimeTextDocument {
        val hasBom = bytes.startsWith(UTF8_BOM)
        val textBytes = if (hasBom) bytes.copyOfRange(UTF8_BOM.size, bytes.size) else bytes
        if (textBytes.any { it == 0.toByte() }) {
            throw RuntimeFileException(
                code = RuntimeFileErrorCode.INVALID_UTF8,
                operation = "readTextDocument",
                message = "NUL bytes are not supported in text documents",
            )
        }
        val text = try {
            StandardCharsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(textBytes))
                .toString()
        } catch (error: Throwable) {
            throw RuntimeFileException(
                code = RuntimeFileErrorCode.INVALID_UTF8,
                operation = "readTextDocument",
                message = "File is not valid UTF-8",
                cause = error,
            )
        }
        return RuntimeTextDocument(
            text = text,
            hasUtf8Bom = hasBom,
            newlineStyle = newlineStyleOf(text),
            hasFinalNewline = text.endsWith('\n') || text.endsWith('\r'),
            sizeBytes = bytes.size.toLong(),
            modifiedAtMillis = stat.modifiedAtMillis(),
            revision = revisionOf(bytes),
        )
    }

    private fun deleteResolved(file: File, stat: StructStat, recursive: Boolean) {
        if (!OsConstants.S_ISDIR(stat.st_mode) || OsConstants.S_ISLNK(stat.st_mode)) {
            Os.remove(file.absolutePath)
            return
        }
        val children = file.listFiles()
            ?: throw RuntimeFileException(
                code = RuntimeFileErrorCode.PERMISSION_DENIED,
                operation = "deleteEntry",
                message = "Directory cannot be listed",
            )
        if (children.isNotEmpty() && !recursive) {
            throw RuntimeFileException(
                code = RuntimeFileErrorCode.DIRECTORY_NOT_EMPTY,
                operation = "deleteEntry",
                message = "Directory is not empty",
            )
        }
        children.forEach { child ->
            val childStat = Os.lstat(child.absolutePath)
            deleteResolved(child, childStat, recursive = true)
        }
        Os.remove(file.absolutePath)
    }

    private fun requireRegularFile(
        stat: StructStat,
        operation: String,
        scope: RootfsScope,
        pathSegments: List<String>,
    ) {
        when {
            OsConstants.S_ISDIR(stat.st_mode) -> throw RuntimeFileException(
                code = RuntimeFileErrorCode.IS_DIRECTORY,
                operation = operation,
                message = "Expected a regular file",
                scopeId = scope.id,
                relativePath = pathSegments.joinToString("/"),
            )
            !OsConstants.S_ISREG(stat.st_mode) -> throw RuntimeFileException(
                code = RuntimeFileErrorCode.UNSUPPORTED_FILE_TYPE,
                operation = operation,
                message = "Unsupported file type",
                scopeId = scope.id,
                relativePath = pathSegments.joinToString("/"),
            )
        }
    }

    private fun requireDirectory(
        stat: StructStat,
        operation: String,
        scope: RootfsScope,
        pathSegments: List<String>,
    ) {
        if (!OsConstants.S_ISDIR(stat.st_mode)) {
            throw RuntimeFileException(
                code = RuntimeFileErrorCode.NOT_DIRECTORY,
                operation = operation,
                message = "Expected a directory",
                scopeId = scope.id,
                relativePath = pathSegments.joinToString("/"),
            )
        }
    }

    private fun requireNotSymlink(
        stat: StructStat,
        operation: String,
        scope: RootfsScope,
        pathSegments: List<String>,
    ) {
        if (OsConstants.S_ISLNK(stat.st_mode)) {
            throw RuntimeFileException(
                code = RuntimeFileErrorCode.SYMLINK_NOT_ALLOWED,
                operation = operation,
                message = "Symbolic links cannot be opened",
                scopeId = scope.id,
                relativePath = pathSegments.joinToString("/"),
            )
        }
    }

    private fun kindOf(stat: StructStat): RootfsFileKind =
        when {
            OsConstants.S_ISREG(stat.st_mode) -> RootfsFileKind.FILE
            OsConstants.S_ISDIR(stat.st_mode) -> RootfsFileKind.DIRECTORY
            OsConstants.S_ISLNK(stat.st_mode) -> RootfsFileKind.SYMLINK
            else -> RootfsFileKind.OTHER
        }

    private fun encodeCursor(entry: RuntimeFileEntry): String =
        Base64.encodeToString(
            "${entry.kind.wireName}\u0000${entry.name}".toByteArray(Charsets.UTF_8),
            Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING,
        )

    private fun decodeCursor(
        cursor: String,
        scope: RootfsScope,
        pathSegments: List<String>,
    ): Pair<String, String> =
        try {
            val decoded = String(
                Base64.decode(cursor, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING),
                Charsets.UTF_8,
            )
            val separator = decoded.indexOf('\u0000')
            require(separator > 0 && separator < decoded.lastIndex)
            decoded.substring(0, separator) to decoded.substring(separator + 1)
        } catch (error: Throwable) {
            throw RuntimeFileException(
                code = RuntimeFileErrorCode.INVALID_PATH,
                operation = "listDirectory",
                message = "Invalid pagination cursor",
                scopeId = scope.id,
                relativePath = pathSegments.joinToString("/"),
                cause = error,
            )
        }

    private fun newlineStyleOf(text: String): RuntimeNewlineStyle {
        var hasLf = false
        var hasCrlf = false
        var index = 0
        while (index < text.length) {
            when (text[index]) {
                '\r' -> {
                    if (index + 1 < text.length && text[index + 1] == '\n') {
                        hasCrlf = true
                        index++
                    } else {
                        hasLf = true
                    }
                }
                '\n' -> hasLf = true
            }
            index++
        }
        return when {
            hasLf && hasCrlf -> RuntimeNewlineStyle.MIXED
            hasCrlf -> RuntimeNewlineStyle.CRLF
            hasLf -> RuntimeNewlineStyle.LF
            else -> RuntimeNewlineStyle.NONE
        }
    }

    private fun revisionOf(bytes: ByteArray): String =
        "sha256:" + MessageDigest.getInstance("SHA-256")
            .digest(bytes)
            .joinToString("") { byte -> "%02x".format(byte) }

    private fun StructStat.modifiedAtMillis(): Long =
        st_mtim.tv_sec * 1000L + st_mtim.tv_nsec / 1_000_000L

    private fun ByteArray.startsWith(prefix: ByteArray): Boolean =
        size >= prefix.size && prefix.indices.all { this[it] == prefix[it] }

    private fun lstatOrNull(file: File): StructStat? =
        try {
            Os.lstat(file.absolutePath)
        } catch (error: ErrnoException) {
            if (error.errno == OsConstants.ENOENT) null else throw error
        }

    private fun removeIfPresent(file: File) {
        try {
            Os.remove(file.absolutePath)
        } catch (error: ErrnoException) {
            if (error.errno != OsConstants.ENOENT) throw error
        }
    }

    private fun fsyncDirectory(directory: File) {
        // O_DIRECTORY 在部分编译目标上不可解析，这里只用 O_RDONLY 打开目录。
        // 在 Linux/Android 上对目录 fd 调用 fsync 同样能确保目录条目变更落盘。
        val descriptor = Os.open(
            directory.absolutePath,
            OsConstants.O_RDONLY,
            0,
        )
        try {
            Os.fsync(descriptor)
        } finally {
            Os.close(descriptor)
        }
    }

    private inline fun <T> withMutationLock(scope: RootfsScope, block: () -> T): T =
        synchronized(mutationLocks.computeIfAbsent(scope.id) { Any() }, block)

    private fun <T> runFileOperation(
        operation: String,
        scope: RootfsScope,
        pathSegments: List<String>,
        block: () -> T,
    ): T =
        try {
            block()
        } catch (error: RuntimeFileException) {
            throw error.withContext(operation, scope, pathSegments)
        } catch (error: ErrnoException) {
            throw mapErrno(error, operation, scope, pathSegments)
        } catch (error: SecurityException) {
            throw RuntimeFileException(
                code = RuntimeFileErrorCode.PERMISSION_DENIED,
                operation = operation,
                message = "File operation was denied",
                scopeId = scope.id,
                relativePath = pathSegments.joinToString("/"),
                cause = error,
            )
        } catch (error: Throwable) {
            throw RuntimeFileException(
                code = RuntimeFileErrorCode.IO_ERROR,
                operation = operation,
                message = "File operation failed",
                scopeId = scope.id,
                relativePath = pathSegments.joinToString("/"),
                retryable = true,
                cause = error,
            )
        }

    private fun RuntimeFileException.withContext(
        operation: String,
        scope: RootfsScope,
        pathSegments: List<String>,
    ): RuntimeFileException =
        if (scopeId != null && relativePath != null) {
            this
        } else {
            RuntimeFileException(
                code = code,
                operation = operation,
                message = message,
                scopeId = scope.id,
                relativePath = pathSegments.joinToString("/"),
                retryable = retryable,
                currentRevision = currentRevision,
                cause = this,
            )
        }

    private fun mapErrno(
        error: ErrnoException,
        operation: String,
        scope: RootfsScope,
        pathSegments: List<String>,
    ): RuntimeFileException {
        val code = when (error.errno) {
            OsConstants.ENOENT -> RuntimeFileErrorCode.NOT_FOUND
            OsConstants.EEXIST -> RuntimeFileErrorCode.ALREADY_EXISTS
            OsConstants.ENOTDIR -> RuntimeFileErrorCode.NOT_DIRECTORY
            OsConstants.EISDIR -> RuntimeFileErrorCode.IS_DIRECTORY
            OsConstants.ENOTEMPTY -> RuntimeFileErrorCode.DIRECTORY_NOT_EMPTY
            OsConstants.EACCES, OsConstants.EPERM -> RuntimeFileErrorCode.PERMISSION_DENIED
            OsConstants.ELOOP -> RuntimeFileErrorCode.SYMLINK_NOT_ALLOWED
            OsConstants.EBUSY -> RuntimeFileErrorCode.BUSY
            else -> RuntimeFileErrorCode.IO_ERROR
        }
        return RuntimeFileException(
            code = code,
            operation = operation,
            message = when (code) {
                RuntimeFileErrorCode.NOT_FOUND -> "Path no longer exists"
                RuntimeFileErrorCode.ALREADY_EXISTS -> "Path already exists"
                RuntimeFileErrorCode.NOT_DIRECTORY -> "Expected a directory"
                RuntimeFileErrorCode.IS_DIRECTORY -> "Expected a regular file"
                RuntimeFileErrorCode.DIRECTORY_NOT_EMPTY -> "Directory is not empty"
                RuntimeFileErrorCode.PERMISSION_DENIED -> "File operation was denied"
                RuntimeFileErrorCode.SYMLINK_NOT_ALLOWED -> "Symbolic links cannot be followed"
                RuntimeFileErrorCode.BUSY -> "File is busy"
                else -> "File operation failed"
            },
            scopeId = scope.id,
            relativePath = pathSegments.joinToString("/"),
            retryable = code == RuntimeFileErrorCode.BUSY || code == RuntimeFileErrorCode.IO_ERROR,
            cause = error,
        )
    }
}

private const val MAX_DIRECTORY_PAGE_SIZE = 500
internal const val MAX_TEXT_FILE_BYTES = 1024 * 1024
private const val DEFAULT_FILE_MODE = 0x1A4 // 0644
private const val DEFAULT_DIRECTORY_MODE = 0x1ED // 0755
private const val PERMISSION_BITS_MASK = 0x1FF // 0777
private val UTF8_BOM = byteArrayOf(0xEF.toByte(), 0xBB.toByte(), 0xBF.toByte())
