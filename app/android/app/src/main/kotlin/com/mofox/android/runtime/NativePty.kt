package com.mofox.android.runtime

internal object NativePty {
    init {
        System.loadLibrary("mofoxpty")
    }

    fun start(
        command: List<String>,
        environment: Map<String, String>,
        cwd: String,
        cols: Int,
        rows: Int,
    ): PtyProcess? {
        val envArray = environment.map { (key, value) -> "$key=$value" }.toTypedArray()
        val result = nativeStart(
            command.toTypedArray(),
            envArray,
            cwd,
            cols,
            rows,
        ) ?: return null
        if (result.size < 2) return null
        return PtyProcess(pid = result[0].toInt(), fd = result[1].toInt())
    }

    external fun nativeStart(
        command: Array<String>,
        environment: Array<String>,
        cwd: String,
        cols: Int,
        rows: Int,
    ): LongArray?

    external fun nativeRead(fd: Int, buffer: ByteArray, offset: Int, length: Int): Int

    external fun nativeWrite(fd: Int, data: ByteArray, offset: Int, length: Int): Int

    external fun nativeResize(fd: Int, cols: Int, rows: Int)

    external fun nativeClose(fd: Int)

    external fun nativeKill(pid: Int)

    external fun nativeWait(pid: Int): Int
}

internal data class PtyProcess(val pid: Int, val fd: Int)