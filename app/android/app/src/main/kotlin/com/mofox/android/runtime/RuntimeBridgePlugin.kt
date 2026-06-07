package com.mofox.android.runtime

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Runtime 总线骨架。
 *
 * MethodChannel  : mofox/runtime           （命令）
 * EventChannel   : mofox/runtime/events    （bootstrap 进度 / pty 输出）
 *
 * 所有方法当前返回桩值或抛 UNIMPLEMENTED。等 BootstrapInstaller / TermuxLauncher
 * 接通后再逐项实现。
 */
class RuntimeBridgePlugin {
    private var sink: EventChannel.EventSink? = null

    fun attach(engine: FlutterEngine, context: Context) {
        MethodChannel(engine.dartExecutor.binaryMessenger, "mofox/runtime")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isBootstrapped" -> result.success(false)
                    "installBootstrap" -> result.success(null) // 进度走 EventChannel topic=bootstrap
                    "startProcess", "stopProcess", "restartProcess" ->
                        result.notImplemented()
                    "processStatus" -> result.success(
                        mapOf("bot" to "stopped", "napcat" to "stopped"),
                    )
                    "openPty", "writePty", "resizePty", "closePty" ->
                        result.notImplemented()
                    else -> result.notImplemented()
                }
            }

        EventChannel(engine.dartExecutor.binaryMessenger, "mofox/runtime/events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    sink = events
                }
                override fun onCancel(arguments: Any?) {
                    sink = null
                }
            })
    }
}
