package com.mofox.android.runtime

import android.content.Context
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

    fun install(progress: (Double) -> Unit): List<String> {
        ensureBaseDirectories()
        if (isBootstrapped()) {
            progress(1.0)
            return listOf("[runtime] bootstrap already installed: ${prefixDir.absolutePath}")
        }

        val assetName = bootstrapAssetName()
        val logs = mutableListOf("[runtime] extracting $assetName")
        try {
            context.assets.open("flutter_assets/assets/runtime/$assetName").use { input ->
                ZipInputStream(input.buffered()).use { zip ->
                    var entry: ZipEntry? = zip.nextEntry
                    var count = 0
                    while (entry != null) {
                        extractEntry(zip, entry)
                        count += 1
                        if (count % 100 == 0) {
                            progress(0.15 + (count % 700) / 1000.0)
                        }
                        zip.closeEntry()
                        entry = zip.nextEntry
                    }
                }
            }
        } catch (error: java.io.FileNotFoundException) {
            throw RuntimeException(
                "Missing runtime asset $assetName. Put bootstrap zip in app/assets/runtime before running install.",
                error,
            )
        }

        markExecutables(prefixDir)
        progress(1.0)
        logs += "[runtime] bootstrap installed: ${prefixDir.absolutePath}"
        return logs
    }

    private fun extractEntry(zip: ZipInputStream, entry: ZipEntry) {
        val relativeName = entry.name.removePrefix("./")
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

    private fun bootstrapAssetName(): String {
        val abi = android.os.Build.SUPPORTED_ABIS.firstOrNull().orEmpty()
        return when {
            abi.contains("arm64") -> "bootstrap-aarch64.zip"
            abi.contains("armeabi") -> "bootstrap-arm.zip"
            abi.contains("x86_64") -> "bootstrap-x86_64.zip"
            else -> "bootstrap-aarch64.zip"
        }
    }
}