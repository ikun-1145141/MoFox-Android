package com.mofox.android.runtime

import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

class RuntimeProcessManager(
    private val installer: BootstrapInstaller,
    private val events: RuntimeEventBus,
) {
    private val executor = Executors.newCachedThreadPool()
    private val commandBuilder = RuntimeCommandBuilder(installer)
    private val scripts = RuntimeScripts(installer)
    private val processes = ConcurrentHashMap<String, ManagedProcess>()

    fun status(): Map<String, String> {
        return mapOf(
            "bot" to statusFor("bot"),
            "napcat" to statusFor("napcat"),
        )
    }

    fun start(name: String) {
        if (!installer.isBootstrapped()) error("Runtime bootstrap is not installed")
        val existing = processes[name]
        if (existing?.process?.isAlive == true) return
        val script = scripts.processScript(name)
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

    fun restart(name: String) {
        stop(name)
        start(name)
    }

    fun runInstallTask(task: String, args: Map<String, String>): InstallTaskResult {
        if (task == "extractRootfs") {
            val logs = installer.install { value -> events.emit("bootstrap", value) }
            return InstallTaskResult(true, logs, null, null)
        }
        if (!installer.isBootstrapped()) {
            return InstallTaskResult(false, emptyList(), null, "Runtime bootstrap is not installed")
        }

        val script = scripts.scriptFor(task, args)
        val builder = ProcessBuilder(commandBuilder.scriptCommand(script))
            .directory(installer.homeDir)
            .redirectErrorStream(true)
        builder.environment().putAll(commandBuilder.environment())

        val process = builder.start()
        val logs = mutableListOf<String>()
        var qrPayload: String? = null
        events.emit("install", mapOf("task" to task, "line" to "[run] native task $task started"))
        BufferedReader(InputStreamReader(process.inputStream)).useLines { lines ->
            lines.forEach { line ->
                logs += line
                events.emit("install", mapOf("task" to task, "line" to line))
                if (line.startsWith("MOFOX_QR_PAYLOAD=")) {
                    qrPayload = line.substringAfter("=")
                }
            }
        }
        val code = process.waitFor()
        events.emit("install", mapOf("task" to task, "line" to "[exit] native task $task exited with $code"))
        return InstallTaskResult(code == 0, logs, qrPayload, if (code == 0) null else "Task $task exited with $code")
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

    fun attach(sink: io.flutter.plugin.common.EventChannel.EventSink?) {
        this.sink = sink
    }

    fun emit(topic: String, payload: Any?) {
        sink?.success(mapOf("topic" to topic, "payload" to payload))
    }
}