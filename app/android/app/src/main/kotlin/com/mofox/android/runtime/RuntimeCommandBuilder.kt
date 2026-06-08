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
        val proot = File(prefix, "bin/proot")
        val bash = File(prefix, "bin/bash").takeIf { it.exists() } ?: File(prefix, "bin/sh")
        val mountedScript = "/mofox-scripts/${script.name}"
        return if (proot.exists()) {
            listOf(
                proot.absolutePath,
                "-0",
                "-r",
                prefix.absolutePath,
                "-b",
                "${home.absolutePath}:/root",
                "-b",
                "${File(prefix, "tmp").absolutePath}:/tmp",
                "-b",
                "/proc",
                "-b",
                "/dev",
                "-b",
                "${installer.scriptsDir.absolutePath}:/mofox-scripts",
                "/usr/bin/env",
                "-i",
                "HOME=/root",
                "PREFIX=/usr",
                "PATH=/usr/bin:/usr/bin/applets:/bin",
                "TMPDIR=/tmp",
                "LANG=C.UTF-8",
                "/bin/bash",
                mountedScript,
            )
        } else {
            listOf(bash.absolutePath, script.absolutePath)
        }
    }
}