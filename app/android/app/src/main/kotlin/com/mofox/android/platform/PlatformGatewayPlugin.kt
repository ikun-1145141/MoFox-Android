package com.mofox.android.platform

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
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
                    "openVendorAutostart" -> {
                        openVendorAutostart(activity)
                        result.success(null)
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        result.success(requestIgnoreBatteryOptimizations(activity))
                    }
                    "startForegroundService" -> {
                        val intent = Intent(ctx, MoFoxForegroundService::class.java)
                        MoFoxForegroundService.setKeepaliveEnabled(ctx, true)
                        ctx.startForegroundService(intent)
                        result.success(null)
                    }
                    "stopForegroundService" -> {
                        MoFoxForegroundService.setKeepaliveEnabled(ctx, false)
                        ctx.stopService(Intent(ctx, MoFoxForegroundService::class.java))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun requestIgnoreBatteryOptimizations(activity: Activity): Boolean {
        val packageName = activity.packageName
        val powerManager = activity.getSystemService(Context.POWER_SERVICE) as PowerManager
        if (powerManager.isIgnoringBatteryOptimizations(packageName)) return true

        val requestIntent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
            data = Uri.parse("package:$packageName")
        }
        return activity.startActivitySafely(requestIntent)
    }

    private fun openVendorAutostart(activity: Activity) {
        val packageName = activity.packageName
        val attempts = listOf(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:$packageName")
            },
            Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS),
            Intent(Settings.ACTION_SETTINGS),
        )
        attempts.firstOrNull { activity.startActivitySafely(it) }
    }

    private fun Activity.startActivitySafely(intent: Intent): Boolean {
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return runCatching {
            startActivity(intent)
        }.isSuccess
    }
}
