package com.mofox.android.platform

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import android.view.WindowManager
import androidx.core.app.NotificationManagerCompat
import com.mofox.android.keepalive.MoFoxForegroundService
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.ByteArrayOutputStream

/**
 * Platform 总线。
 *
 * MethodChannel : mofox/platform
 *
 * 提供 SAF 文件导出/导入、保活提示、前台服务开关。
 */
class PlatformGatewayPlugin : PluginRegistry.ActivityResultListener {

    companion object {
        private const val REQ_EXPORT = 10001
        private const val REQ_IMPORT = 10002
    }

    private var activity: Activity? = null
    private var pendingExportBytes: ByteArray? = null
    private var pendingResult: MethodChannel.Result? = null

    fun attach(engine: FlutterEngine, activity: Activity) {
        this.activity = activity
        val ctx: Context = activity.applicationContext

        MethodChannel(engine.dartExecutor.binaryMessenger, "mofox/platform")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "exportToSaf" -> {
                        val suggestedName = call.argument<String>("suggestedName") ?: "export.zip"
                        val bytes = call.argument<ByteArray>("bytes")
                        if (bytes == null) {
                            result.error("MISSING_BYTES", "bytes is required", null)
                            return@setMethodCallHandler
                        }
                        pendingExportBytes = bytes
                        pendingResult = result
                        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "application/zip"
                            putExtra(Intent.EXTRA_TITLE, suggestedName)
                        }
                        activity.startActivityForResult(intent, REQ_EXPORT)
                    }
                    "importFromSaf" -> {
                        pendingResult = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "*/*"
                            val mimeTypes = arrayOf(
                                "application/zip",
                                "application/x-tar",
                                "application/x-xz",
                                "application/octet-stream",
                            )
                            putExtra(Intent.EXTRA_MIME_TYPES, mimeTypes)
                        }
                        activity.startActivityForResult(intent, REQ_IMPORT)
                    }
                    "openVendorAutostart" -> {
                        openVendorAutostart(activity)
                        result.success(null)
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        result.success(requestIgnoreBatteryOptimizations(activity))
                    }
                    "getKeepaliveStatus" -> {
                        result.success(getKeepaliveStatus(activity))
                    }
                    "setKeepScreenOn" -> {
                        setKeepScreenOn(activity, call.argument<Boolean>("enabled") == true)
                        result.success(null)
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

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        val ctx = activity?.applicationContext ?: return false
        val res = pendingResult
        if (res == null) return false

        when (requestCode) {
            REQ_EXPORT -> {
                val uri = data?.data
                val bytes = pendingExportBytes
                if (uri != null && bytes != null && resultCode == Activity.RESULT_OK) {
                    try {
                        ctx.contentResolver.openOutputStream(uri)?.use { out ->
                            out.write(bytes)
                        }
                        res.success(uri.toString())
                    } catch (e: Exception) {
                        res.error("SAF_EXPORT_FAILED", e.message, null)
                    }
                } else {
                    res.success(null)
                }
                pendingExportBytes = null
                pendingResult = null
                return true
            }
            REQ_IMPORT -> {
                val uri = data?.data
                if (uri != null && resultCode == Activity.RESULT_OK) {
                    try {
                        val bytes = ctx.contentResolver.openInputStream(uri)?.use { inp ->
                            val buf = ByteArrayOutputStream()
                            inp.copyTo(buf)
                            buf.toByteArray()
                        }
                        if (bytes != null) {
                            res.success(bytes)
                        } else {
                            res.error("SAF_IMPORT_FAILED", "Cannot read file", null)
                        }
                    } catch (e: Exception) {
                        res.error("SAF_IMPORT_FAILED", e.message, null)
                    }
                } else {
                    res.success(null)
                }
                pendingResult = null
                return true
            }
        }
        return false
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

    private fun getKeepaliveStatus(activity: Activity): Map<String, Any> {
        val packageName = activity.packageName
        val powerManager = activity.getSystemService(Context.POWER_SERVICE) as PowerManager
        return mapOf(
            "notificationsGranted" to NotificationManagerCompat.from(activity).areNotificationsEnabled(),
            "ignoringBatteryOptimizations" to powerManager.isIgnoringBatteryOptimizations(packageName),
            "foregroundServiceEnabled" to MoFoxForegroundService.isKeepaliveEnabled(activity.applicationContext),
            "bootReceiverDeclared" to true,
            "vendorAutostartInspectable" to false,
        )
    }

    private fun setKeepScreenOn(activity: Activity, enabled: Boolean) {
        activity.runOnUiThread {
            if (enabled) {
                activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            } else {
                activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            }
        }
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
