package com.mofox.android.platform

import android.app.Activity
import android.content.Context
import android.content.Intent
import com.mofox.android.keepalive.MoFoxForegroundService
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Platform 总线骨架。
 *
 * MethodChannel : mofox/platform
 *
 * 提供 SAF 文件导出、保活提示、前台服务开关。
 * 当前 SAF 与 vendor autostart 桩返回 null / false，等 UI 接通后再补 ActivityResult。
 */
class PlatformGatewayPlugin {
    fun attach(engine: FlutterEngine, activity: Activity) {
        val ctx: Context = activity.applicationContext
        MethodChannel(engine.dartExecutor.binaryMessenger, "mofox/platform")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "exportToSaf" -> result.success(null)
                    "openVendorAutostart" -> result.success(false)
                    "startForegroundService" -> {
                        val intent = Intent(ctx, MoFoxForegroundService::class.java)
                        ctx.startForegroundService(intent)
                        result.success(null)
                    }
                    "stopForegroundService" -> {
                        ctx.stopService(Intent(ctx, MoFoxForegroundService::class.java))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
