package com.mofox.android.runtime

import java.io.File

class RuntimeCommandBuilder(private val installer: BootstrapInstaller) {
    private val prefix: File = installer.prefixDir
    private val home: File = installer.homeDir

    fun environment(): MutableMap<String, String> {
        val path = listOf(
            File(prefix, "bin").absolutePath,
            File(prefix, "bin/applets").absolutePath,
            "/system/bin",
        ).joinToString(":")
        return mutableMapOf(
            "PREFIX" to prefix.absolutePath,
            "HOME" to home.absolutePath,
            "PATH" to path,
            "TMPDIR" to File(prefix, "tmp").absolutePath,
            "LD_LIBRARY_PATH" to File(prefix, "lib").absolutePath,
            "LANG" to "C.UTF-8",
        )
    }

    fun scriptCommand(script: File): List<String> {
        val bash = File(prefix, "bin/bash").takeIf { it.exists() } ?: File(prefix, "bin/sh")
        return listOf(bash.absolutePath, script.absolutePath)
    }
}