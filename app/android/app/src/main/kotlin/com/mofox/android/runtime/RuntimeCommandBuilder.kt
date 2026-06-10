package com.mofox.android.runtime

import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import android.content.Context
import java.io.File

/**
 * 构建 host 层 shell 进程使用的环境变量与命令行。
 *
 * jniLibs 模型：所有原生二进制（proot/bash/busybox/sudo/loader/talloc）由 Android
 * 解压到 `applicationInfo.nativeLibraryDir`，该目录被打了 SELinux exec 标，可以
 * 直接通过完整路径执行。脚本永远跑在 host 层 bash（libbash.so）下，再由脚本里的
 * `login_ubuntu` 函数走 proot 进入 Ubuntu。
 */
class RuntimeCommandBuilder(
    private val context: Context,
    private val installer: RootfsInstaller,
) {
    val nativeLibraryDir: String = context.applicationInfo.nativeLibraryDir

    /**
     * jniLibs 强制 `lib*.so` 命名，所以 `libtalloc.so.2` 落盘成 `liblibtalloc.so.2.so`。
     * proot 的 DT_NEEDED 写的是真名 `libtalloc.so.2`，Android linker 不会自己映射，
     * 需要在一个可写目录里建 symlink 喂给它。
     */
    private val libAliasDir: File = File(context.filesDir, "runtime-libs")

    private val libAliases: Map<String, String> = mapOf(
        "libtalloc.so.2" to "liblibtalloc.so.2.so",
    )

    private fun ensureLibAliases() {
        libAliasDir.mkdirs()
        for ((alias, real) in libAliases) {
            val link = File(libAliasDir, alias)
            val target = "$nativeLibraryDir/$real"
            link.delete()
            try {
                Os.symlink(target, link.absolutePath)
            } catch (e: ErrnoException) {
                if (e.errno != OsConstants.EEXIST) throw e
            }
        }
    }

    fun environment(): MutableMap<String, String> {
        ensureLibAliases()
        return mutableMapOf(
            "BIN" to nativeLibraryDir,
            "PROOT_LOADER" to "$nativeLibraryDir/libloader.so",
            "LD_LIBRARY_PATH" to "${libAliasDir.absolutePath}:$nativeLibraryDir",
            "PROOT_TMP_DIR" to installer.tmpDir.absolutePath,
            "TMPDIR" to installer.tmpDir.absolutePath,
            "HOME" to installer.homeDir.absolutePath,
            "HOME_PATH" to installer.homeDir.absolutePath,
            "USR_PATH" to installer.prefixDir.absolutePath,
            "UBUNTU_PATH" to installer.ubuntuPath.absolutePath,
            "PATH" to "$nativeLibraryDir:/system/bin:/system/xbin",
            "LANG" to "C.UTF-8",
        )
    }

    /** host 层 bash 入口：libbash.so 当作 bash 跑指定脚本。 */
    fun scriptCommand(script: File): List<String> {
        return listOf("$nativeLibraryDir/libbash.so", script.absolutePath)
    }
}
