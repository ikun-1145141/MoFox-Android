package com.mofox.android.runtime

import android.content.Context
import android.system.Os
import java.io.File
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream

class BootstrapInstaller(private val context: Context) {
    private val filesDir: File = context.filesDir
    val prefixDir: File = File(filesDir, "usr")
    val homeDir: File = File(filesDir, "home")
    val scriptsDir: File = File(filesDir, "mofox-scripts")

    fun isBootstrapped(): Boolean {
        return File(prefixDir, "bin").isDirectory && File(prefixDir, "bin/sh").exists()
    }

    fun ensureBaseDirectories() {
        homeDir.mkdirs()
        scriptsDir.mkdirs()
        File(prefixDir, "tmp").mkdirs()
    }

    fun install(
        onProgress: (Double) -> Unit,
        onLog: (String) -> Unit = {},
    ): List<String> {
        ensureBaseDirectories()
        if (isBootstrapped()) {
            onProgress(1.0)
            val msg = "[runtime] bootstrap already installed: ${prefixDir.absolutePath}"
            onLog(msg)
            return listOf(msg)
        }

        val assetName = bootstrapAssetName()
        val assetPath = "flutter_assets/assets/runtime/$assetName"
        val logs = mutableListOf<String>()
        fun log(line: String) {
            logs += line
            onLog(line)
        }

        // 预检：确认 zip 真的存在且不是 0 字节占位符。否则 UI 会停在 3% 看不出失败。
        validateBootstrapAsset(assetName, assetPath, ::log)

        log("[runtime] extracting $assetName")
        onProgress(0.05)

        val symlinks = mutableListOf<BootstrapSymlink>()
        try {
            context.assets.open(assetPath).use { input ->
                ZipInputStream(input.buffered()).use { zip ->
                    var entry: ZipEntry? = zip.nextEntry
                    var count = 0
                    while (entry != null) {
                        if (isSymlinkManifest(entry)) {
                            symlinks += readSymlinks(zip)
                        } else {
                            extractEntry(zip, entry)
                        }
                        count += 1
                        if (count % 200 == 0) {
                            log("[runtime] extracted $count entries (current: ${entry.name})")
                            // 没法预先知道总条目数，给个缓慢逼近 0.9 的估值。
                            val ratio = 1.0 - (1.0 / (1.0 + count / 800.0))
                            onProgress(0.05 + 0.85 * ratio)
                        }
                        zip.closeEntry()
                        entry = zip.nextEntry
                    }
                    log("[runtime] extracted $count entries total")
                }
            }
        } catch (error: java.util.zip.ZipException) {
            throw RuntimeException(
                "Runtime asset $assetName is not a valid zip: ${error.message}. " +
                    "Re-download bootstrap from termux/termux-packages and place it at app/assets/runtime/$assetName.",
                error,
            )
        }

        log("[runtime] creating ${symlinks.size} symlinks")
        onProgress(0.93)
        createSymlinks(symlinks)
        log("[runtime] marking executables")
        onProgress(0.97)
        markExecutables(prefixDir)
        onProgress(1.0)
        log("[runtime] bootstrap installed: ${prefixDir.absolutePath}")
        return logs
    }

    private fun extractEntry(zip: ZipInputStream, entry: ZipEntry) {
        val relativeName = normalizedEntryName(entry.name)
        if (relativeName.isBlank()) return
        val target = File(prefixDir, relativeName).canonicalFile
        if (!target.path.startsWith(prefixDir.canonicalPath)) {
            throw SecurityException("Zip entry escapes prefix: ${entry.name}")
        }
        if (entry.isDirectory) {
            target.mkdirs()
            return
        }

        target.parentFile?.mkdirs()
        target.outputStream().use { output -> zip.copyTo(output) }
        if (isExecutablePath(relativeName)) {
            target.setExecutable(true, false)
        }
    }

    private fun markExecutables(dir: File) {
        listOf("bin", "libexec").forEach { child ->
            File(dir, child).walkTopDown()
                .filter { it.isFile }
                .forEach { it.setExecutable(true, false) }
        }
    }

    private fun isExecutablePath(path: String): Boolean {
        return path.startsWith("bin/") || path.startsWith("libexec/") || path.endsWith(".sh")
    }

    private fun isSymlinkManifest(entry: ZipEntry): Boolean {
        return entry.name.removePrefix("./") == "SYMLINKS.txt"
    }

    private fun readSymlinks(zip: ZipInputStream): List<BootstrapSymlink> {
        return zip.readBytes().toString(Charsets.UTF_8)
            .lineSequence()
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .map { line ->
                val parts = line.split("←")
                if (parts.size != 2) {
                    throw RuntimeException("Malformed bootstrap symlink line: $line")
                }
                BootstrapSymlink(target = parts[0], linkName = normalizedEntryName(parts[1]))
            }
            .toList()
    }

    private fun createSymlinks(symlinks: List<BootstrapSymlink>) {
        symlinks.forEach { symlink ->
            val link = File(prefixDir, symlink.linkName).canonicalFile
            if (!link.path.startsWith(prefixDir.canonicalPath)) {
                throw SecurityException("Symlink escapes prefix: ${symlink.linkName}")
            }
            link.parentFile?.mkdirs()
            if (link.exists()) link.delete()
            Os.symlink(symlink.target, link.absolutePath)
        }
    }

    private fun normalizedEntryName(name: String): String {
        return name.removePrefix("./").removePrefix("usr/")
    }

    private fun bootstrapAssetName(): String {
        val abi = android.os.Build.SUPPORTED_ABIS.firstOrNull().orEmpty()
        return when {
            abi.contains("arm64") -> "bootstrap-aarch64.zip"
            abi.contains("armeabi") -> "bootstrap-arm.zip"
            abi.contains("x86_64") -> "bootstrap-x86_64.zip"
            else -> "bootstrap-aarch64.zip"
        }
    }

    private fun validateBootstrapAsset(
        assetName: String,
        assetPath: String,
        log: (String) -> Unit,
    ) {
        // openFd 拿不到长度（assets 里 zip 是 stored，无 fd 窗口大小），所以直接读头 4 字节验 magic。
        val head: ByteArray
        try {
            head = context.assets.open(assetPath).use { input ->
                val buf = ByteArray(4)
                var read = 0
                while (read < buf.size) {
                    val n = input.read(buf, read, buf.size - read)
                    if (n <= 0) break
                    read += n
                }
                buf.copyOf(read)
            }
        } catch (error: java.io.FileNotFoundException) {
            throw RuntimeException(
                "Runtime asset $assetName is missing from the APK. " +
                    "Place bootstrap zip at app/assets/runtime/$assetName before building. " +
                    "See app/assets/runtime/README.md for the upstream link.",
                error,
            )
        }
        if (head.size < 4) {
            throw RuntimeException(
                "Runtime asset $assetName is empty (read ${head.size} bytes). " +
                    "Replace app/assets/runtime/$assetName with a real bootstrap zip from termux-packages.",
            )
        }
        val isZip = head[0] == 0x50.toByte() &&
            head[1] == 0x4B.toByte() &&
            (head[2] == 0x03.toByte() || head[2] == 0x05.toByte() || head[2] == 0x07.toByte())
        if (!isZip) {
            val hex = head.joinToString("") { String.format("%02X", it) }
            throw RuntimeException(
                "Runtime asset $assetName has invalid zip magic (got $hex). " +
                    "The file at app/assets/runtime/$assetName is not a real bootstrap zip.",
            )
        }
        log("[runtime] asset $assetName ok (zip magic verified)")
    }
}

private data class BootstrapSymlink(val target: String, val linkName: String)