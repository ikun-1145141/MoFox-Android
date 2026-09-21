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
import java.util.concurrent.atomic.AtomicReference

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
    private val assistantProcess = AtomicReference<Process?>(null)

    fun status(): Map<String, String> {
        val botStatus = statusFor("bot")
        val napcatStatus = statusFor("napcat")
        val botInstanceId = processes["bot"]?.args?.get("instanceId")
            ?.takeIf { botStatus == "running" && it.isNotBlank() }
        val napcatInstanceId = processes["napcat"]?.args?.get("instanceId")
            ?.takeIf { napcatStatus == "running" && it.isNotBlank() }
        val activeInstanceId = (botInstanceId ?: napcatInstanceId).orEmpty()
        return mapOf(
            "bot" to botStatus,
            "napcat" to napcatStatus,
            "activeInstanceId" to activeInstanceId,
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
                // napcat 进程树复杂（proot → bash → xvfb-run → Xvfb + QQ），
                // stop 脚本在另一个 proot 里用 pgrep -f 扫描 /proc（即 host 的 /proc），
                // 可能误杀 napcat 自己的 proot（managed.process）导致 consumeProcess
                // 读到 broken pipe、甚至级联崩溃整个 app。
                // 直接 destroy 根 proot 进程即可让整棵树级联退出。
                if (name != "napcat") {
                    runStopScript(name, managed.args)
                }
                managed.process?.destroy()
                // 给 SIGTERM 2 秒，然后强制 SIGKILL
                if (managed.process?.waitFor(2, TimeUnit.SECONDS) == false) {
                    managed.process?.destroyForcibly()
                    managed.process?.waitFor(3, TimeUnit.SECONDS)
                }
            }
            // process 设为 null，防止 statusFor 通过 isAlive 误判已杀的进程
            processes[name] = ManagedProcess(null, "stopped", managed?.args ?: emptyMap())
        } finally {
            stopping.remove(name)
        }
    }

    fun restart(name: String, args: Map<String, String> = emptyMap()) {
        stop(name)
        start(name, args)
    }

    @Synchronized
    fun runAssistantCommand(command: String, cwd: String, unrestricted: Boolean = false): AssistantCommandResult {
        if (!installer.isBootstrapped()) error("Runtime bootstrap is not installed")
        validateAssistantCommand(command, cwd, unrestricted)
        if (assistantProcess.get()?.isAlive == true) error("An assistant command is already running")
        val script = scripts.assistantCommandScript(cwd, command)
        val builder = ProcessBuilder(commandBuilder.scriptCommand(script))
            .directory(installer.homeDir)
            .redirectErrorStream(true)
        builder.environment().putAll(commandBuilder.environment())
        val process = builder.start()
        if (!assistantProcess.compareAndSet(null, process)) {
            process.destroyForcibly()
            error("An assistant command is already running")
        }
        val output = StringBuilder()
        var truncated = false
        val reader = executor.submit {
            val buffer = CharArray(2048)
            InputStreamReader(process.inputStream, Charsets.UTF_8).use { stream ->
                while (true) {
                    val count = stream.read(buffer)
                    if (count <= 0) break
                    if (output.length < MAX_ASSISTANT_OUTPUT_CHARS) {
                        val remaining = MAX_ASSISTANT_OUTPUT_CHARS - output.length
                        output.append(buffer, 0, minOf(count, remaining))
                        if (count > remaining) truncated = true
                    } else {
                        truncated = true
                    }
                }
            }
        }
        var timedOut = false
        val exitCode = try {
            if (process.waitFor(ASSISTANT_TIMEOUT_SECONDS, TimeUnit.SECONDS)) {
                process.exitValue()
            } else {
                timedOut = true
                process.destroyForcibly()
                process.waitFor(5, TimeUnit.SECONDS)
                -1
            }
        } finally {
            try {
                reader.get(5, TimeUnit.SECONDS)
            } finally {
                assistantProcess.compareAndSet(process, null)
            }
        }
        return AssistantCommandResult(exitCode, output.toString(), timedOut, truncated)
    }

    fun cancelAssistantCommand() {
        assistantProcess.getAndSet(null)?.destroyForcibly()
    }

    private fun validateAssistantCommand(command: String, cwd: String, unrestricted: Boolean) {
        require(command.isNotBlank() && command.length <= 512) { "Invalid assistant command length" }
        require(command.none { it.code < 0x20 || it.code == 0x7f }) { "Control characters are forbidden" }
        require(cwd.length <= 512 && cwd.split('/').none { it == ".." }) { "Invalid assistant cwd" }
        require(cwd == "/root" || cwd.startsWith("/root/instances/")) { "Assistant cwd is outside the allowed scope" }
        if (unrestricted) return
        require(!Regex("[;&|><`]|\\$\\(").containsMatchIn(command)) { "Shell operators are forbidden" }
        require(!Regex("(?i)(api[_-]?key|password|token|cookie|secret|/etc/(shadow|passwd)|\\.ssh/)").containsMatchIn(command)) {
            "Sensitive data access is forbidden"
        }
        require(!Regex("(?i)(^|\\s)(/sdcard|/storage|/data|/dev|/sys|/proc/[^\\s]*/(environ|cmdline)|/root/\\.[^\\s]*)").containsMatchIn(command)) {
            "Private paths are forbidden"
        }
        require(!Regex("(^|\\s)\\.\\.(/|\\s|$)").containsMatchIn(command)) { "Parent traversal is forbidden" }
        val parts = command.trim().split(Regex("\\s+"))
        val executable = parts.first().lowercase()
        val allowed = setOf("pwd", "ls", "df", "du", "free", "uname", "id", "whoami", "date", "uptime", "git", "python", "python3", "pip", "pip3")
        require(executable in allowed) { "Command is not in the assistant allowlist" }
        if (executable == "git") {
            require(parts.getOrNull(1) in setOf("status", "branch", "rev-parse")) {
                "Only read-only git commands are allowed"
            }
        }
        if (executable == "python" || executable == "python3") {
            require(parts.getOrNull(1) in setOf("--version", "-V", "--help", "-h")) {
                "Python code execution is forbidden"
            }
        }
        if (executable == "pip" || executable == "pip3") {
            require(parts.getOrNull(1) in setOf("list", "show", "check")) {
                "Package changes are forbidden"
            }
        }
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

    /** 取消正在进行的 napcatLogin 任务：在 rootfs 内写 cancel 标记文件。 */
    fun cancelNapcatLogin() {
        try {
            val cancelFile = File(installer.ubuntuPath, "tmp/napcat-login.cancel")
            cancelFile.parentFile?.mkdirs()
            cancelFile.writeText("cancel")
        } catch (e: Throwable) {
            events.emit("install", mapOf("task" to "napcatLogin", "line" to "[napcat] cancel failed: ${e.message}"))
        }
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
        try {
            BufferedReader(InputStreamReader(process.inputStream)).useLines { lines ->
                lines.forEach { line ->
                    // napcat 进程脚本输出 MOFOX_QR_IMAGE=<rootfs_path>，
                    // 映射为 host 层 file: 路径供 Dart 端显示 QR 图片。
                    val eventLine = if (name == "napcat" && line.startsWith("MOFOX_QR_IMAGE=")) {
                        val hostPath = mapUbuntuPathToHost(line.substringAfter("="))
                        "MOFOX_QR_IMAGE=$hostPath"
                    } else {
                        line
                    }
                    events.emit("process", mapOf("name" to name, "line" to eventLine))
                }
            }
        } catch (e: java.io.InterruptedIOException) {
            // 进程被 stop()/destroy() 中断读取，属正常退出路径，忽略。
        } catch (e: java.io.IOException) {
            // 流已关闭（destroy/destroyForcibly），属正常退出路径，忽略。
        }
        val code = try { process.waitFor() } catch (_: InterruptedException) { -1 }
        // restart() 会先停旧进程再立即登记新进程。旧进程的读取线程可能稍后才
        // 走到这里，不能让它把已经登记的新进程覆盖成 stopped。
        processes.computeIfPresent(name) { _, managed ->
            if (managed.process === process) {
                ManagedProcess(process, "stopped", managed.args)
            } else {
                managed
            }
        }
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
private const val MAX_ASSISTANT_OUTPUT_CHARS = 32_768
private const val ASSISTANT_TIMEOUT_SECONDS = 30L

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

data class AssistantCommandResult(
    val exitCode: Int,
    val output: String,
    val timedOut: Boolean,
    val truncated: Boolean,
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
