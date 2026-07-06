package com.mofox.android.runtime

import android.content.Context
import android.os.Handler
import android.os.Looper
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class RuntimeProcessManager(
    context: Context,
    val installer: RootfsInstaller,
    private val events: RuntimeEventBus,
) {
    private val executor = Executors.newCachedThreadPool()
    val commandBuilder = RuntimeCommandBuilder(context, installer)
    val scripts = RuntimeScripts(installer, commandBuilder)
    private val processes = ConcurrentHashMap<String, ManagedProcess>()
    /** 正在进行的 stop/restart 操作标记，防止快速点击导致并发停止脚本互相打架。 */
    private val stopping = ConcurrentHashMap<String, Boolean>()

    fun status(): Map<String, String> {
        return mapOf(
            "bot" to statusFor("bot"),
            "napcat" to statusFor("napcat"),
        )
    }

    fun start(name: String, args: Map<String, String> = emptyMap()) {
        if (!installer.isBootstrapped()) error("Runtime bootstrap is not installed")
        val existing = processes[name]
        if (existing?.process?.isAlive == true) return
        val script = scripts.processScript(name, args)
        val builder = ProcessBuilder(commandBuilder.scriptCommand(script))
            .directory(installer.homeDir)
            .redirectErrorStream(true)
        builder.environment().putAll(commandBuilder.environment())
        val process = builder.start()
        processes[name] = ManagedProcess(process, "running", args)
        executor.execute { consumeProcess(name, process) }
    }

    fun stop(name: String) {
        // 并发保护：如果该进程已经在停止中，直接返回，避免快速点击触发多个 stop 脚本
        // 同时 spawn 多个 pgrep/kill，可能误杀 host 层 bash/proot 导致整个 app 崩溃。
        if (stopping.putIfAbsent(name, true) != null) return
        try {
            val managed = processes[name]
            if (managed != null) {
                runStopScript(name, managed.args)
                managed.process?.destroy()
            }
            processes[name] = ManagedProcess(managed?.process, "stopped", managed?.args ?: emptyMap())
        } finally {
            stopping.remove(name)
        }
    }

    fun restart(name: String, args: Map<String, String> = emptyMap()) {
        stop(name)
        start(name, args)
    }

    fun runInstallTask(task: String, args: Map<String, String>): InstallTaskResult {
        if (task == "extractRootfs") {
            val stageLogs = try {
                installer.install(
                    onProgress = { value -> events.emit("bootstrap", value) },
                    onLog = { line -> events.emit("install", mapOf("task" to task, "line" to line)) },
                )
            } catch (error: Throwable) {
                val msg = error.message ?: "staging failed"
                return InstallTaskResult(false, emptyList(), null, msg)
            }
            val shellResult = runShellTask(task, args)
            val mergedLogs = stageLogs + shellResult.logs
            if (!shellResult.success) {
                return shellResult.copy(logs = mergedLogs)
            }
            if (!installer.isBootstrapped()) {
                val msg = "rootfs extracted but ${installer.ubuntuPath} still missing /usr/bin/env or /etc/os-release (Debian 13 trixie)"
                return InstallTaskResult(false, mergedLogs, null, msg)
            }
            return shellResult.copy(logs = mergedLogs)
        }
        if (!installer.isBootstrapped()) {
            return InstallTaskResult(false, emptyList(), null, "Runtime bootstrap is not installed")
        }
        // installNapcat 需要先把本地 napcat-install.sh 拷进 rootfs
        if (task == "installNapcat") {
            try {
                installer.stageNapcatInstaller()
            } catch (e: Throwable) {
                return InstallTaskResult(false, emptyList(), null, e.message ?: "stageNapcatInstaller failed")
            }
        }
        return runShellTask(task, args)
    }

    private fun runShellTask(task: String, args: Map<String, String>): InstallTaskResult {
        val script = scripts.scriptFor(task, args)
        val builder = ProcessBuilder(commandBuilder.scriptCommand(script))
            .directory(installer.homeDir)
            .redirectErrorStream(true)
        builder.environment().putAll(commandBuilder.environment())

        val process = builder.start()
        val logs = ArrayDeque<String>()
        var qrPayload: String? = null
        BufferedReader(InputStreamReader(process.inputStream)).useLines { lines ->
            lines.forEach { line ->
                logs.addBounded(line)
                val eventLine = when {
                    line.startsWith("MOFOX_QR_IMAGE=") -> {
                        val hostPath = mapUbuntuPathToHost(line.substringAfter("="))
                        "MOFOX_QR_PAYLOAD=file:$hostPath"
                    }
                    else -> line
                }
                events.emit("install", mapOf("task" to task, "line" to eventLine))
                if (eventLine.startsWith("MOFOX_QR_PAYLOAD=")) {
                    qrPayload = eventLine.substringAfter("=")
                }
            }
        }
        val code = process.waitForWithTimeout()
        return InstallTaskResult(code == 0, logs.toList(), qrPayload, if (code == 0) null else "Task $task exited with $code")
    }

    /**
     * 带超时的 waitFor：最多等 [timeoutSeconds] 秒，超时后强制销毁进程。
     * 防止 proot 挂起导致单线程执行器永久阻塞。
     */
    private fun Process.waitForWithTimeout(timeoutSeconds: Long = 60): Int {
        if (waitFor(timeoutSeconds, TimeUnit.SECONDS)) return exitValue()
        // 超时：强制杀进程
        destroyForcibly()
        waitFor(5, TimeUnit.SECONDS)
        return -1
    }

    private fun mapUbuntuPathToHost(path: String): String {
        val cleanPath = path.trim()
        if (!cleanPath.startsWith("/")) return cleanPath
        return File(installer.ubuntuPath, cleanPath.removePrefix("/")).absolutePath
    }

    private fun runStopScript(name: String, args: Map<String, String>) {
        if (!installer.isBootstrapped()) return
        val script = scripts.stopProcessScript(name, args)
        val builder = ProcessBuilder(commandBuilder.scriptCommand(script))
            .directory(installer.homeDir)
            .redirectErrorStream(true)
        builder.environment().putAll(commandBuilder.environment())
        try {
            val process = builder.start()
            BufferedReader(InputStreamReader(process.inputStream)).useLines { lines ->
                lines.forEach { line -> events.emit("process", mapOf("name" to name, "line" to line)) }
            }
            // stop 脚本里有 sleep 2，给 15 秒兜底，避免卡死 executor 线程。
            process.waitForWithTimeout(15)
        } catch (error: Throwable) {
            events.emit("process", mapOf("name" to name, "line" to "[$name] stop failed: ${error.message}"))
        }
    }

    private fun consumeProcess(name: String, process: Process) {
        BufferedReader(InputStreamReader(process.inputStream)).useLines { lines ->
            lines.forEach { line -> events.emit("process", mapOf("name" to name, "line" to line)) }
        }
        val code = process.waitFor()
        val managed = processes[name]
        processes[name] = ManagedProcess(process, "stopped", managed?.args ?: emptyMap())
        events.emit("process", mapOf("name" to name, "line" to "[$name] exited with $code"))
    }

    private fun statusFor(name: String): String {
        val managed = processes[name] ?: return "stopped"
        return if (managed.process?.isAlive == true) "running" else managed.state
    }
}

private fun ArrayDeque<String>.addBounded(line: String) {
    if (size == MAX_INSTALL_RESULT_LOG_LINES) removeFirst()
    addLast(line)
}

private const val MAX_INSTALL_RESULT_LOG_LINES = 300

data class ManagedProcess(
    val process: Process?,
    val state: String,
    val args: Map<String, String> = emptyMap(),
)

data class InstallTaskResult(
    val success: Boolean,
    val logs: List<String>,
    val qrPayload: String?,
    val error: String?,
)

class RuntimeEventBus {
    @Volatile
    private var sink: io.flutter.plugin.common.EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    fun attach(sink: io.flutter.plugin.common.EventChannel.EventSink?) {
        this.sink = sink
    }

    fun emit(topic: String, payload: Any?) {
        val event = mapOf("topic" to topic, "payload" to payload)
        if (Looper.myLooper() == Looper.getMainLooper()) {
            sink?.success(event)
        } else {
            mainHandler.post { sink?.success(event) }
        }
    }
}