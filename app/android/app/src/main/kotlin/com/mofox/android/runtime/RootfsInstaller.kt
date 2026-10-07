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
     * 把 APK 内置的插件包（assets/plugins 目录下的 .mfp 文件）铺到 rootfs 的
     * `/root/.mofox/plugin-cache/`。bot 进程脚本启动时从这里复制进实例的
     * plugins/ 目录——每次启动都执行，旧实例无需重装即可获得插件，升级
     * APK 即可升级插件。文件不存在时静默跳过（兼容未打包的构建）。
     *
     * 当前清单仅含短信桥插件：QQ 适配器使用 bot 仓库自带的 onebot_adapter
     * （无需分发）；本函数保留铺发机制供未来插件使用。
     */
    fun stageBundledPlugins() {
        ensureBaseDirectories()
        val cacheDir = File(ubuntuPath, "root/.mofox/plugin-cache")
        cacheDir.mkdirs()
        val names = listOf(
            "mofox_sms_bridge-1.0.0.mfp",
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
        // 引擎启动跳板（arm64 预编译，源码见 assets/scripts/snowluma-trampoline.c）：
        // 铺到 rootfs /usr/local/lib/，snowluma 进程脚本把它追加进 QQ 的
        // LD_PRELOAD 链（LD_PRELOAD=hook.so:trampoline.so）。文件不存在时
        // 静默跳过（兼容未打包的构建）。
        try {
            context.assets.open("flutter_assets/assets/scripts/snowluma-trampoline.so").use { input ->
                val soDir = File(ubuntuPath, "usr/local/lib")
                soDir.mkdirs()
                File(soDir, "snowluma-trampoline.so").outputStream().buffered().use { output ->
                    input.copyTo(output)
                }
            }
        } catch (e: java.io.FileNotFoundException) {
            // 该构建未打包跳板资产时跳过，不影响 SnowLuma 启动。
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
        // 长度校验标记：只在完整拷贝后写入。中断的拷贝（杀后台/存储压力）
        // 留下的残缺包没有标记，会在下次启动时被识别并重新铺发——否则
        // "存在且 size>0 即跳过" 会把残缺包当有效，解压阶段
        // busybox xz 读到截断流崩溃（proot vpid terminated with signal 11），
        // 且重试永远复用同一个坏包。
        val sizeMarker = File(homeDir, "$ubuntuTarballName.size")

        if (target.exists() && sizeMarker.exists()) {
            val recorded = sizeMarker.readText().trim().toLongOrNull()
            if (recorded != null && recorded > 0 && recorded == target.length()) {
                val msg = "[runtime] $ubuntuTarballName already staged (${target.length()} bytes)"
                logs += msg
                onLog(msg)
                onProgress(1.0)
                return logs
            }
            val msg =
                "[runtime] $ubuntuTarballName 大小与校验标记不符 " +
                    "(${target.length()} != $recorded)，重新从 assets 铺发"
            logs += msg
            onLog(msg)
            target.delete()
            sizeMarker.delete()
        } else if (target.exists()) {
            // 旧版本遗留的无标记文件（可能残缺）：重新铺发以确保完整。
            val msg = "[runtime] $ubuntuTarballName 无校验标记，重新从 assets 铺发以确保完整"
            logs += msg
            onLog(msg)
            target.delete()
        }

        val assetRelativePath = "flutter_assets/assets/rootfs/$ubuntuTarballName"
        val startMsg = "[runtime] staging $ubuntuTarballName from assets"
        logs += startMsg
        onLog(startMsg)
        onProgress(0.05)

        // 拷到临时文件后原子落位：进程被杀只会留下残缺的 .tmp（下次启动
        // 清掉重来），target 上永远不会出现"看似有效"的半截包。
        val tmpTarget = File(homeDir, "$ubuntuTarballName.tmp")
        tmpTarget.delete()
        try {
            context.assets.open(assetRelativePath).use { input ->
                tmpTarget.outputStream().buffered(BUFFER_SIZE).use { output ->
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
            tmpTarget.delete()
            throw RuntimeException(
                "缺少 rootfs 资源：$assetRelativePath。请先运行 tools/build.py 把 Debian 13 rootfs 下载到 app/assets/rootfs/。",
                error,
            )
        }

        if (!tmpTarget.renameTo(target)) {
            // 个别文件系统 rename 跨场景失败：退化为主要拷贝路径。
            tmpTarget.copyTo(target, overwrite = true)
            tmpTarget.delete()
        }
        sizeMarker.writeText(target.length().toString())

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
