package com.mofox.android.runtime

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Runtime 总线。
 *
 * MethodChannel  : mofox/runtime           （命令）
 * EventChannel   : mofox/runtime/events    （bootstrap 进度 / pty 输出）
 *
 * 第一阶段实现 bootstrap、安装任务、bot/napcat 长进程启停；PTY 后续接 JNI。
 */
class RuntimeBridgePlugin {
    private val events = RuntimeEventBus()
    private val executor = Executors.newSingleThreadExecutor()

    fun attach(engine: FlutterEngine, context: Context) {
        val installer = BootstrapInstaller(context.applicationContext)
        val processManager = RuntimeProcessManager(installer, events)

        MethodChannel(engine.dartExecutor.binaryMessenger, "mofox/runtime")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isBootstrapped" -> result.success(installer.isBootstrapped())
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
                        processManager.start(call.requireName())
                        null
                    }
                    "stopProcess" -> runAsync(result) {
                        processManager.stop(call.requireName())
                        null
                    }
                    "restartProcess" -> runAsync(result) {
                        processManager.restart(call.requireName())
                        null
                    }
                    "processStatus" -> result.success(processManager.status())
                    "openPty", "writePty", "resizePty", "closePty" ->
                        result.notImplemented()
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
}
