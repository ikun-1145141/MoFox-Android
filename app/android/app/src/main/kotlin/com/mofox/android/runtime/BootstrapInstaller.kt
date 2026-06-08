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

    fun install(progress: (Double) -> Unit): List<String> {
        ensureBaseDirectories()
        if (isBootstrapped()) {
            progress(1.0)
            return listOf("[runtime] bootstrap already installed: ${prefixDir.absolutePath}")
        }

        val assetName = bootstrapAssetName()
        val logs = mutableListOf("[runtime] extracting $assetName")
        val symlinks = mutableListOf<BootstrapSymlink>()
        try {
            context.assets.open("flutter_assets/assets/runtime/$assetName").use { input ->
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

        createSymlinks(symlinks)
        markExecutables(prefixDir)
        progress(1.0)
        logs += "[runtime] bootstrap installed: ${prefixDir.absolutePath}"
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
}

private data class BootstrapSymlink(val target: String, val linkName: String)