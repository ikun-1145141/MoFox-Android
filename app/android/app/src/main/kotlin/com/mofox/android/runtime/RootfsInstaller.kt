package com.mofox.android.runtime

import android.content.Context
import java.io.File

/**
 * Debian 13 (trixie) rootfs 安装器。变量名仍叫 ubuntu*，纯标识符。
 *
 * 落盘布局：
 * - `<filesDir>/usr/var/lib/proot-distro/installed-rootfs/ubuntu` 解压后的 rootfs 根
 * - `<filesDir>/home`        host 层 HOME，里面会落 tar.xz 与启动脚本
 * - `<filesDir>/tmp`         host 层 TMPDIR
 * - `<filesDir>/mofox-scripts` 由 [RuntimeScripts] 落的一次性任务脚本
 *
 * 真正的解压由 shell 脚本里的 `install_ubuntu` 用 `libbusybox.so tar xJvf ...` 完成；
 * Kotlin 这边只负责把 assets 里的 tar.xz 拷到 HOME，并提供路径常量。
 */
class RootfsInstaller(private val context: Context) {
    val filesDir: File = context.filesDir
    val prefixDir: File = File(filesDir, "usr")
    val homeDir: File = File(filesDir, "home")
    val scriptsDir: File = File(filesDir, "mofox-scripts")
    val tmpDir: File = File(filesDir, "tmp")
    val ubuntuPath: File = File(prefixDir, "var/lib/proot-distro/installed-rootfs/ubuntu")

    private val abiSuffix: String = computeAbiSuffix()
    val ubuntuTarballName: String = "debian-13-$abiSuffix.tar.xz"

    fun isBootstrapped(): Boolean {
        return File(ubuntuPath, "usr/bin/env").exists() &&
            File(ubuntuPath, "etc/os-release").exists()
    }

    /**
     * 把 `flutter_assets/assets/scripts/napcat-install.sh` 拷到 rootfs 内的
     * `/usr/local/bin/napcat-install.sh`，供 installNapcat 任务体直接执行。
     * 幂等：文件已存在且大小一致则跳过。
     */
    fun stageNapcatInstaller(): File {
        ensureBaseDirectories()
        val target = File(ubuntuPath, "usr/local/bin/napcat-install.sh")
        if (target.exists() && target.length() > 0) return target
        ubuntuPath.mkdirs()
        File(ubuntuPath, "usr/local/bin").mkdirs()
        try {
            context.assets.open("flutter_assets/assets/scripts/napcat-install.sh").use { input ->
                target.outputStream().buffered().use { output -> input.copyTo(output) }
            }
            target.setExecutable(true, false)
        } catch (e: java.io.FileNotFoundException) {
            throw RuntimeException("缺少 assets/scripts/napcat-install.sh", e)
        }
        return target
    }

    fun ensureBaseDirectories() {
        homeDir.mkdirs()
        scriptsDir.mkdirs()
        tmpDir.mkdirs()
        prefixDir.mkdirs()
        ubuntuPath.parentFile?.mkdirs()
    }

    /**
     * 把 `flutter_assets/assets/rootfs/<tar.xz>` 拷到 `$HOME/<tar.xz>`。
     * 后续 shell 里的 `install_ubuntu` 直接引用 `~/${'$'}UBUNTU` 完成解压。
     */
    fun install(
        onProgress: (Double) -> Unit,
        onLog: (String) -> Unit,
    ): List<String> {
        ensureBaseDirectories()
        val logs = mutableListOf<String>()
        val target = File(homeDir, ubuntuTarballName)

        if (target.exists() && target.length() > 0) {
            val msg = "[runtime] $ubuntuTarballName already staged (${target.length()} bytes)"
            logs += msg
            onLog(msg)
            onProgress(1.0)
            return logs
        }

        val assetRelativePath = "flutter_assets/assets/rootfs/$ubuntuTarballName"
        val startMsg = "[runtime] staging $ubuntuTarballName from assets"
        logs += startMsg
        onLog(startMsg)
        onProgress(0.05)

        try {
            context.assets.open(assetRelativePath).use { input ->
                target.outputStream().buffered(BUFFER_SIZE).use { output ->
                    val buffer = ByteArray(BUFFER_SIZE)
                    var totalCopied: Long = 0
                    var lastReported: Long = 0
                    var bytesRead = input.read(buffer)
                    while (bytesRead != -1) {
                        output.write(buffer, 0, bytesRead)
                        totalCopied += bytesRead
                        if (totalCopied - lastReported >= PROGRESS_TICK_BYTES) {
                            lastReported = totalCopied
                            val mb = totalCopied / 1024 / 1024
                            onLog("[runtime] copied ${mb}MiB")
                            onProgress(0.05 + (totalCopied.toDouble() / EST_TARBALL_BYTES).coerceAtMost(0.9))
                        }
                        bytesRead = input.read(buffer)
                    }
                }
            }
        } catch (error: java.io.FileNotFoundException) {
            throw RuntimeException(
                "缺少 rootfs 资源：$assetRelativePath。请先运行 tools/build.py 把 Debian 13 rootfs 下载到 app/assets/rootfs/。",
                error,
            )
        }

        val doneMsg = "[runtime] staged $ubuntuTarballName -> ${target.absolutePath} (${target.length()} bytes)"
        logs += doneMsg
        onLog(doneMsg)
        onProgress(1.0)
        return logs
    }

    private fun computeAbiSuffix(): String {
        val abi = android.os.Build.SUPPORTED_ABIS.firstOrNull().orEmpty()
        return when {
            abi.contains("arm64") -> "arm64"
            abi.contains("armeabi") -> "armhf"
            abi.contains("x86_64") -> "amd64"
            else -> "arm64"
        }
    }

    companion object {
        private const val BUFFER_SIZE = 64 * 1024
        private const val PROGRESS_TICK_BYTES = 16L * 1024 * 1024
        private const val EST_TARBALL_BYTES = 350.0 * 1024 * 1024
    }
}
