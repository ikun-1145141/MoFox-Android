package com.mofox.android.runtime

import android.content.Context
import android.os.Handler
import android.os.Looper
import java.io.BufferedReader
import java.io.InputStreamReader
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

class RuntimeProcessManager(
    context: Context,
    val installer: RootfsInstaller,
    private val events: RuntimeEventBus,
) {
    private val executor = Executors.newCachedThreadPool()
    val commandBuilder = RuntimeCommandBuilder(context, installer)
    val scripts = RuntimeScripts(installer, commandBuilder)
    private val processes = ConcurrentHashMap<String, ManagedProcess>()

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
        processes[name] = ManagedProcess(process, "running")
        executor.execute { consumeProcess(name, process) }
    }

    fun stop(name: String) {
        processes[name]?.process?.destroy()
        processes[name] = ManagedProcess(processes[name]?.process, "stopped")
    }

    fun restart(name: String, args: Map<String, String> = emptyMap()) {
        stop(name)
        start(name, args)
    }

    fun runInstallTask(task: String, args: Map<String, String>): InstallTaskResult {
        if (task == "extractRootfs") {
            events.emit("install", mapOf("task" to task, "line" to "[run] staging rootfs tarball from assets…"))
            val stageLogs = try {
                installer.install(
                    onProgress = { value -> events.emit("bootstrap", value) },
                    onLog = { line -> events.emit("install", mapOf("task" to task, "line" to line)) },
                )
            } catch (error: Throwable) {
                val msg = error.message ?: "staging failed"
                events.emit("install", mapOf("task" to task, "line" to "[error] $msg"))
                return InstallTaskResult(false, emptyList(), null, msg)
            }
            val shellResult = runShellTask(task, args)
            val mergedLogs = stageLogs + shellResult.logs
            if (!shellResult.success) {
                return shellResult.copy(logs = mergedLogs)
            }
            if (!installer.isBootstrapped()) {
                val msg = "rootfs extracted but ${installer.ubuntuPath} still missing /usr/bin/env or /etc/os-release (Debian 13 trixie)"
                events.emit("install", mapOf("task" to task, "line" to "[error] $msg"))
                return InstallTaskResult(false, mergedLogs, null, msg)
            }
            return shellResult.copy(logs = mergedLogs)
        }
        if (!installer.isBootstrapped()) {
            return InstallTaskResult(false, emptyList(), null, "Runtime bootstrap is not installed")
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
        events.emit("install", mapOf("task" to task, "line" to "[run] native task $task started"))
        BufferedReader(InputStreamReader(process.inputStream)).useLines { lines ->
            lines.forEach { line ->
                logs.addBounded(line)
                events.emit("install", mapOf("task" to task, "line" to line))
                if (line.startsWith("MOFOX_QR_PAYLOAD=")) {
                    qrPayload = line.substringAfter("=")
                }
            }
        }
        val code = process.waitFor()
        events.emit("install", mapOf("task" to task, "line" to "[exit] native task $task exited with $code"))
        return InstallTaskResult(code == 0, logs.toList(), qrPayload, if (code == 0) null else "Task $task exited with $code")
    }

    private fun consumeProcess(name: String, process: Process) {
        BufferedReader(InputStreamReader(process.inputStream)).useLines { lines ->
            lines.forEach { line -> events.emit("process", mapOf("name" to name, "line" to line)) }
        }
        val code = process.waitFor()
        processes[name] = ManagedProcess(process, "stopped")
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

data class ManagedProcess(val process: Process?, val state: String)

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