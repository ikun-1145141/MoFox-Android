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
     * 把 `flutter_assets/assets/scripts/snowluma-install.sh` 拷到 rootfs 内的
     * `/usr/local/bin/snowluma-install.sh`，供 installSnowluma 任务体直接执行。
     * 每次调用都无条件覆盖：rootfs 会跨 APK 覆盖安装存活，若按"存在即跳过"，
     * 旧版 APK 留下的脚本会一直被执行，必须与 APK 内置脚本保持一致。
     * 拷贝时统一 CRLF→LF 并去掉 UTF-8 BOM：Windows 构建机打出的 APK 资产
     * 可能带 CRLF，bash 会把 `set -e\r` 的 \r 当成选项名（"无效的选项"）。
     */
    fun stageSnowlumaInstaller(): File {
        ensureBaseDirectories()
        val target = File(ubuntuPath, "usr/local/bin/snowluma-install.sh")
        ubuntuPath.mkdirs()
        File(ubuntuPath, "usr/local/bin").mkdirs()
        try {
            context.assets.open("flutter_assets/assets/scripts/snowluma-install.sh").use { input ->
                val raw = input.readBytes()
                var text = raw.toString(Charsets.UTF_8).replace("\uFEFF", "")
                text = text.replace("\r\n", "\n").replace('\r', '\n')
                target.outputStream().buffered().use { output ->
                    output.write(text.toByteArray(Charsets.UTF_8))
                }
            }
            target.setExecutable(true, false)
        } catch (e: java.io.FileNotFoundException) {
            throw RuntimeException("缺少 assets/scripts/snowluma-install.sh", e)
        }
        return target
    }

    /**
     * 把 APK 内置的 SnowLuma 适配器插件包（`assets/plugins/snowluma_*.mfp`）
     * 铺到 rootfs 的 `/root/.mofox/plugin-cache/`。bot 进程脚本启动时从这里
     * 复制进实例的 plugins/ 目录——每次启动都执行，旧实例无需重装即可获得插件，
     * 升级 APK 即可升级插件。文件不存在时静默跳过（兼容未打包的构建）。
     */
    fun stageSnowlumaPlugins() {
        ensureBaseDirectories()
        val cacheDir = File(ubuntuPath, "root/.mofox/plugin-cache")
        cacheDir.mkdirs()
        val names = listOf(
            "snowluma_adapter-2.2.10.mfp",
            "snowluma_extension-1.0.11.mfp",
        )
        for (name in names) {
            try {
                context.assets.open("flutter_assets/assets/plugins/$name").use { input ->
                    File(cacheDir, name).outputStream().buffered().use { output ->
                        input.copyTo(output)
                    }
                }
            } catch (e: java.io.FileNotFoundException) {
                // 该构建未打包插件资产时跳过，不影响 bot 启动。
            }
        }
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
