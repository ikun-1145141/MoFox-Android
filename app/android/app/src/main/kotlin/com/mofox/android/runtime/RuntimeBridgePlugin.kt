package com.mofox.android.runtime

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.os.Environment
import android.os.StatFs
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/**
 * Runtime 总线。
 *
 * MethodChannel  : mofox/runtime           （命令）
 * EventChannel   : mofox/runtime/events    （bootstrap 进度 / process / pty 输出）
 *
 * Shell（终端页用）走 native forkpty。xterm 的输入输出、resize、全屏应用控制序列都
 * 通过 PTY 传递，nano/top 这类程序才能按真实终端工作。
 */
class RuntimeBridgePlugin {
    private val events = RuntimeEventBus()
    private val executor = Executors.newSingleThreadExecutor()
    private val shellExecutor = Executors.newCachedThreadPool()
    private val shellSessions = ConcurrentHashMap<String, ShellSession>()

    fun attach(engine: FlutterEngine, context: Context) {
        val appContext = context.applicationContext
        val installer = RootfsInstaller(appContext)
        val processManager = RuntimeProcessManager(appContext, installer, events)

        MethodChannel(engine.dartExecutor.binaryMessenger, "mofox/runtime")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isBootstrapped" -> result.success(installer.isBootstrapped())
                    "getNativeLibraryDir" ->
                        result.success(appContext.applicationInfo.nativeLibraryDir)
                    "installBootstrap" -> runAsync(result) {
                        installer.install(
                            onProgress = { value -> events.emit("bootstrap", value) },
                            onLog = { line ->
                                events.emit(
                                    "install",
                                    mapOf("task" to "extractRootfs", "line" to line),
                                )
                            },
                        )
                        null
                    }
                    "runInstallTask" -> runAsync(result) {
                        val task = call.argument<String>("task") ?: error("Missing task")
                        val args = call.argument<Map<String, String>>("args") ?: emptyMap()
                        processManager.runInstallTask(task, args).toMap()
                    }
                    "startProcess" -> runAsync(result) {
                        val name = call.requireName()
                        val args = call.argument<Map<String, String>>("args") ?: emptyMap()
                        processManager.start(name, args)
                        null
                    }
                    "stopProcess" -> runAsync(result) {
                        processManager.stop(call.requireName())
                        null
                    }
                    "restartProcess" -> runAsync(result) {
                        val name = call.requireName()
                        val args = call.argument<Map<String, String>>("args") ?: emptyMap()
                        processManager.restart(name, args)
                        null
                    }
                    "processStatus" -> result.success(processManager.status())
                    "systemStats" -> runAsync(result) { systemStats(appContext) }
                    "openShell" -> runAsync(result) {
                        val cwd = call.argument<String>("cwd") ?: "/root"
                        openShell(processManager, cwd)
                    }
                    "writeShell" -> runAsync(result) {
                        val sessionId = call.argument<String>("sessionId")
                            ?: error("Missing sessionId")
                        val data = call.argument<String>("data") ?: ""
                        writeShell(sessionId, data)
                        null
                    }
                    "resizeShell" -> runAsync(result) {
                        val sessionId = call.argument<String>("sessionId")
                            ?: error("Missing sessionId")
                        val cols = call.argument<Int>("cols") ?: 80
                        val rows = call.argument<Int>("rows") ?: 24
                        resizeShell(sessionId, cols, rows)
                        null
                    }
                    "closeShell" -> runAsync(result) {
                        val sessionId = call.argument<String>("sessionId")
                            ?: error("Missing sessionId")
                        closeShell(sessionId)
                        null
                    }
                    "readFile" -> runAsync(result) {
                        val path = call.argument<String>("path") ?: error("Missing path")
                        readFileFromRootfs(installer, path)
                    }
                    "fileExists" -> runAsync(result) {
                        val path = call.argument<String>("path") ?: error("Missing path")
                        fileExistsInRootfs(installer, path)
                    }
                    "listDir" -> runAsync(result) {
                        val path = call.argument<String>("path") ?: error("Missing path")
                        listDirInRootfs(installer, path)
                    }
                    "packToTar" -> runAsync(result) {
                        val paths = call.argument<List<String>>("paths") ?: error("Missing paths")
                        val dest = call.argument<String>("dest") ?: error("Missing dest")
                        packToTarInRootfs(processManager, paths, dest)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(engine.dartExecutor.binaryMessenger, "mofox/runtime/events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    this@RuntimeBridgePlugin.events.attach(events)
                }
                override fun onCancel(arguments: Any?) {
                    this@RuntimeBridgePlugin.events.attach(null)
                }
            })
    }

    private fun openShell(processManager: RuntimeProcessManager, cwd: String): String {
        val sessionId = UUID.randomUUID().toString()
        val script = processManager.scripts.interactiveShellScript(cwd)
        val pty = NativePty.start(
            command = processManager.commandBuilder.scriptCommand(script),
            environment = processManager.commandBuilder.environment(),
            cwd = processManager.installer.homeDir.absolutePath,
            cols = 80,
            rows = 24,
        ) ?: error("Failed to start PTY shell")
        val session = ShellSession(pty)
        shellSessions[sessionId] = session

        shellExecutor.execute {
            val buffer = ByteArray(4096)
            try {
                while (true) {
                    val read = NativePty.nativeRead(session.pty.fd, buffer, 0, buffer.size)
                    if (read <= 0) break
                    val chunk = String(buffer, 0, read, Charsets.UTF_8)
                    events.emit("pty", mapOf("sessionId" to sessionId, "data" to chunk))
                }
            } catch (_: Throwable) {
                // stream closed — fall through to exit notify
            }
            val code = try { NativePty.nativeWait(session.pty.pid) } catch (_: Throwable) { -1 }
            events.emit(
                "pty",
                mapOf("sessionId" to sessionId, "data" to "\r\n[shell exited with $code]\r\n", "exit" to code),
            )
            shellSessions.remove(sessionId)
        }
        return sessionId
    }

    private fun writeShell(sessionId: String, data: String) {
        val session = shellSessions[sessionId] ?: return
        try {
            val bytes = data.toByteArray(Charsets.UTF_8)
            NativePty.nativeWrite(session.pty.fd, bytes, 0, bytes.size)
        } catch (_: Throwable) {
            // pipe broken — session reader will emit exit notice
        }
    }

    private fun resizeShell(sessionId: String, cols: Int, rows: Int) {
        val session = shellSessions[sessionId] ?: return
        NativePty.nativeResize(session.pty.fd, cols, rows)
    }

    private fun closeShell(sessionId: String) {
        val session = shellSessions.remove(sessionId) ?: return
        try { NativePty.nativeKill(session.pty.pid) } catch (_: Throwable) {}
        try { NativePty.nativeClose(session.pty.fd) } catch (_: Throwable) {}
    }

    private fun systemStats(context: Context): Map<String, Any?> {
        val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memoryInfo = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memoryInfo)

        val dataStats = StatFs(Environment.getDataDirectory().absolutePath)
        val appStats = StatFs(context.filesDir.absolutePath)
        val totalMemory = memoryInfo.totalMem
        val availableMemory = memoryInfo.availMem
        val totalStorage = dataStats.blockCountLong * dataStats.blockSizeLong
        val availableStorage = dataStats.availableBlocksLong * dataStats.blockSizeLong

        return mapOf(
            "memoryTotal" to totalMemory,
            "memoryAvailable" to availableMemory,
            "memoryUsed" to totalMemory - availableMemory,
            "storageTotal" to totalStorage,
            "storageAvailable" to availableStorage,
            "storageUsed" to totalStorage - availableStorage,
            "appDataTotal" to appStats.blockCountLong * appStats.blockSizeLong,
            "appDataAvailable" to appStats.availableBlocksLong * appStats.blockSizeLong,
            "deviceName" to listOf(Build.MANUFACTURER, Build.MODEL)
                .filter { it.isNotBlank() }
                .joinToString(" "),
            "socName" to socName(),
            "androidVersion" to Build.VERSION.RELEASE,
            "sdkInt" to Build.VERSION.SDK_INT,
            "supportedAbis" to Build.SUPPORTED_ABIS.joinToString(", "),
            "kernel" to System.getProperty("os.version").orEmpty(),
            "rootfsPath" to File(context.filesDir, "usr").absolutePath,
            "appDataPath" to context.filesDir.absolutePath,
        )
    }

    private fun socName(): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val model = listOf(Build.SOC_MANUFACTURER, Build.SOC_MODEL)
                .filter { it.isNotBlank() && it != "unknown" }
                .joinToString(" ")
            if (model.isNotBlank()) return model
        }
        return listOf(Build.HARDWARE, Build.BOARD)
            .filter { it.isNotBlank() && it != "unknown" }
            .distinct()
            .joinToString(" ")
    }

    private fun runAsync(
        result: MethodChannel.Result,
        block: () -> Any?,
    ) {
        executor.execute {
            try {
                result.success(block())
            } catch (error: Throwable) {
                result.error("RUNTIME_ERROR", error.message, null)
            }
        }
    }

    private fun io.flutter.plugin.common.MethodCall.requireName(): String {
        return argument<String>("name") ?: error("Missing process name")
    }

    private fun InstallTaskResult.toMap(): Map<String, Any?> {
        return mapOf(
            "success" to success,
            "logs" to logs,
            "qrPayload" to qrPayload,
            "error" to error,
        )
    }

    private fun readFileFromRootfs(
        installer: RootfsInstaller,
        rootfsPath: String,
    ): String {
        val cleanPath = rootfsPath.removePrefix("/")
        val file = File(installer.ubuntuPath, cleanPath)
        if (!file.exists()) return ""
        return file.readText()
    }

    private fun fileExistsInRootfs(
        installer: RootfsInstaller,
        rootfsPath: String,
    ): Boolean {
        val cleanPath = rootfsPath.removePrefix("/")
        return File(installer.ubuntuPath, cleanPath).exists()
    }

    private fun listDirInRootfs(
        installer: RootfsInstaller,
        rootfsPath: String,
    ): List<Map<String, Any>> {
        val cleanPath = rootfsPath.removePrefix("/")
        val dir = File(installer.ubuntuPath, cleanPath)
        if (!dir.exists() || !dir.isDirectory) return emptyList()
        return dir.listFiles()?.map { f ->
            mapOf(
                "name" to f.name,
                "isDir" to f.isDirectory,
                "size" to f.length(),
            )
        } ?: emptyList()
    }

    private fun packToTarInRootfs(
        processManager: RuntimeProcessManager,
        paths: List<String>,
        destPath: String,
    ): String {
        val script = processManager.scripts.packTarScript(paths, destPath)
        val builder = ProcessBuilder(processManager.commandBuilder.scriptCommand(script))
            .directory(processManager.installer.homeDir)
            .redirectErrorStream(true)
        builder.environment().putAll(processManager.commandBuilder.environment())
        val process = builder.start()
        val output = process.inputStream.bufferedReader().readText()
        val code = process.waitFor()
        if (code != 0) {
            error("tar failed (code=$code): $output")
        }
        val cleanDest = destPath.removePrefix("/")
        return File(processManager.installer.ubuntuPath, cleanDest).absolutePath
    }
}

private data class ShellSession(val pty: PtyProcess)
