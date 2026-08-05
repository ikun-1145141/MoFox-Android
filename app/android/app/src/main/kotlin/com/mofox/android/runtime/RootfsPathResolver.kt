package com.mofox.android.runtime

import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import android.system.StructStat
import java.io.File

internal data class ResolvedRootfsPath(
    val scope: RootfsScope,
    val scopeRoot: File,
    val target: File,
    val pathSegments: List<String>,
    val stat: StructStat?,
)

/**
 * Resolves a named rootfs scope without following symbolic links.
 *
 * Every public file operation must pass through this class. Host paths are kept
 * entirely on the Android side and are never serialized over MethodChannel.
 */
internal class RootfsPathResolver(private val rootfsRoot: File) {
    fun resolve(
        scope: RootfsScope,
        pathSegments: List<String>,
        operation: String,
        allowMissingLeaf: Boolean = false,
    ): ResolvedRootfsPath {
        validateScope(scope, operation)
        validateSegments(pathSegments, operation, scope)

        val rootStat = lstatOrNull(rootfsRoot)
            ?: fail(
                RuntimeFileErrorCode.ROOTFS_NOT_READY,
                operation,
                scope,
                pathSegments,
                "Runtime rootfs is not ready",
            )
        requireDirectory(rootStat, operation, scope, emptyList())
        requireNotSymlink(rootStat, operation, scope, emptyList())

        val scopeRoot = scopeRoot(scope)
        val scopeStat = lstatOrNull(scopeRoot)
            ?: fail(
                RuntimeFileErrorCode.SCOPE_NOT_FOUND,
                operation,
                scope,
                pathSegments,
                "File scope is not available",
            )
        requireNotSymlink(scopeStat, operation, scope, emptyList())
        requireDirectory(scopeStat, operation, scope, emptyList())

        var current = scopeRoot
        var currentStat: StructStat? = scopeStat
        pathSegments.forEachIndexed { index, segment ->
            current = File(current, segment)
            val isLeaf = index == pathSegments.lastIndex
            currentStat = lstatOrNull(current)
            if (currentStat == null) {
                if (allowMissingLeaf && isLeaf) return@forEachIndexed
                fail(
                    RuntimeFileErrorCode.NOT_FOUND,
                    operation,
                    scope,
                    pathSegments.take(index + 1),
                    "Path no longer exists",
                )
            }
            if (!isLeaf) {
                requireNotSymlink(
                    currentStat,
                    operation,
                    scope,
                    pathSegments.take(index + 1),
                )
                requireDirectory(
                    currentStat,
                    operation,
                    scope,
                    pathSegments.take(index + 1),
                )
            }
        }

        return ResolvedRootfsPath(
            scope = scope,
            scopeRoot = scopeRoot,
            target = current,
            pathSegments = pathSegments.toList(),
            stat = currentStat,
        )
    }

    fun requireMutableTarget(resolved: ResolvedRootfsPath, operation: String) {
        if (resolved.pathSegments.isEmpty()) {
            fail(
                RuntimeFileErrorCode.ROOT_OPERATION_FORBIDDEN,
                operation,
                resolved.scope,
                resolved.pathSegments,
                "The scope root cannot be modified",
            )
        }
    }

    fun validateName(name: String, operation: String, scope: RootfsScope) {
        validateSegments(listOf(name), operation, scope)
    }

    fun restat(resolved: ResolvedRootfsPath, operation: String): StructStat =
        lstatOrNull(resolved.target)
            ?: fail(
                RuntimeFileErrorCode.NOT_FOUND,
                operation,
                resolved.scope,
                resolved.pathSegments,
                "Path no longer exists",
            )

    fun ensureParentChain(resolved: ResolvedRootfsPath, operation: String) {
        val parentSegments = resolved.pathSegments.dropLast(1)
        resolve(
            scope = resolved.scope,
            pathSegments = parentSegments,
            operation = operation,
        )
    }

    private fun scopeRoot(scope: RootfsScope): File {
        val instanceRoot = File(rootfsRoot, "root/instances/${scope.instanceId}")
        return when (scope.kind) {
            RootfsScopeKind.INSTANCE -> instanceRoot
            RootfsScopeKind.REPOSITORY -> File(instanceRoot, "Neo-MoFox")
        }
    }

    private fun validateScope(scope: RootfsScope, operation: String) {
        validateSingleSegment(scope.instanceId, operation, scope, "Invalid instance id")
        val expectedRoot = "/root/instances/${scope.instanceId}"
        if (scope.instanceRootPath != null && scope.instanceRootPath != expectedRoot) {
            fail(
                RuntimeFileErrorCode.PATH_ESCAPE,
                operation,
                scope,
                emptyList(),
                "Instance scope does not match its id",
            )
        }
    }

    private fun validateSegments(
        segments: List<String>,
        operation: String,
        scope: RootfsScope,
    ) {
        segments.forEach { segment ->
            validateSingleSegment(segment, operation, scope, "Invalid relative path")
        }
    }

    private fun validateSingleSegment(
        segment: String,
        operation: String,
        scope: RootfsScope,
        message: String,
    ) {
        if (
            segment.isEmpty() ||
            segment == "." ||
            segment == ".." ||
            '/' in segment ||
            '\\' in segment ||
            '\u0000' in segment
        ) {
            fail(
                RuntimeFileErrorCode.INVALID_PATH,
                operation,
                scope,
                emptyList(),
                message,
            )
        }
    }

    private fun lstatOrNull(file: File): StructStat? =
        try {
            Os.lstat(file.absolutePath)
        } catch (error: ErrnoException) {
            if (error.errno == OsConstants.ENOENT) null else throw error
        }

    private fun requireNotSymlink(
        stat: StructStat,
        operation: String,
        scope: RootfsScope,
        segments: List<String>,
    ) {
        if (OsConstants.S_ISLNK(stat.st_mode)) {
            fail(
                RuntimeFileErrorCode.SYMLINK_NOT_ALLOWED,
                operation,
                scope,
                segments,
                "Symbolic links cannot be traversed",
            )
        }
    }

    private fun requireDirectory(
        stat: StructStat,
        operation: String,
        scope: RootfsScope,
        segments: List<String>,
    ) {
        if (!OsConstants.S_ISDIR(stat.st_mode)) {
            fail(
                RuntimeFileErrorCode.NOT_DIRECTORY,
                operation,
                scope,
                segments,
                "Expected a directory",
            )
        }
    }

    private fun fail(
        code: RuntimeFileErrorCode,
        operation: String,
        scope: RootfsScope,
        pathSegments: List<String>,
        message: String,
    ): Nothing =
        throw RuntimeFileException(
            code = code,
            operation = operation,
            message = message,
            scopeId = scope.id,
            relativePath = pathSegments.joinToString("/"),
        )
}
