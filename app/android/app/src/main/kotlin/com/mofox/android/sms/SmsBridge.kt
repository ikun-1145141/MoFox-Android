package com.mofox.android.sms

import android.content.Context
import android.util.Log
import com.mofox.android.runtime.RootfsInstaller
import java.io.File

/**
 * 短信桥接：把手机收到的短信以 JSONL 追加写入 rootfs 的
 * `/root/.mofox/sms_bridge/inbox.jsonl`，供 proot 内 Neo-MoFox 的
 * mofox_sms_bridge 插件轮询消费（识别快递/取件码等，主动私信主人）。
 *
 * 每行一条事件：
 * `{"v":1,"source":"sms","id":"...","ts":1696...,"sender":"...","body":"..."}`
 *
 * 落盘路径直接用 rootfs 真实目录（App 私有 filesDir 内），不经过 /sdcard
 * bind，规避分区存储对 Android/data 的可见性限制。写入开关由设置页控制，
 * 默认关闭；权限被撤销时自动视为关闭。
 */
object SmsBridge {

    private const val TAG = "SmsBridge"
    private const val PREFS = "sms_bridge_prefs"
    private const val KEY_ENABLED = "enabled"
    private const val MAX_FILE_BYTES = 512L * 1024

    /** 已收到的事件数（进程生命周期内的计数，仅供 UI 展示）。 */
    var sessionEventCount: Int = 0
        private set

    /** 最近一次写入事件的时间戳（epoch ms），0 表示本会话尚未写入。 */
    var lastEventAtMs: Long = 0
        private set

    fun isEnabled(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_ENABLED, false)

    fun setEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_ENABLED, enabled)
            .apply()
    }

    /** rootfs 是否已解压就绪（未就绪时桥接目录无法落盘）。 */
    fun isRootfsReady(context: Context): Boolean =
        RootfsInstaller(context).isBootstrapped()

    fun bridgeDir(context: Context): File =
        File(RootfsInstaller(context).ubuntuPath, "root/.mofox/sms_bridge")

    fun inboxFile(context: Context): File = File(bridgeDir(context), "inbox.jsonl")

    /**
     * 追加一条短信事件。开关关闭 / rootfs 未就绪时静默忽略。
     *
     * @return 是否实际写入了事件。
     */
    @Synchronized
    fun appendEvent(context: Context, sender: String, body: String, eventId: String): Boolean {
        if (!isEnabled(context)) return false
        if (!isRootfsReady(context)) {
            Log.w(TAG, "rootfs 未就绪，丢弃短信事件")
            return false
        }
        if (sender.isBlank() && body.isBlank()) return false

        return try {
            val dir = bridgeDir(context)
            dir.mkdirs()
            val inbox = inboxFile(context)
            rotateIfNeeded(inbox)
            val payload = org.json.JSONObject().apply {
                put("v", 1)
                put("source", "sms")
                put("id", eventId)
                put("ts", System.currentTimeMillis())
                put("sender", sender)
                put("body", body)
            }
            inbox.appendText(payload.toString() + "\n", Charsets.UTF_8)
            sessionEventCount += 1
            lastEventAtMs = System.currentTimeMillis()
            true
        } catch (e: Exception) {
            Log.e(TAG, "写入短信桥接事件失败", e)
            false
        }
    }

    /** 写入一条模拟快递短信，供设置页「发送测试」验证端到端链路。 */
    fun appendTestEvent(context: Context): Boolean {
        val id = "test-${System.currentTimeMillis()}"
        return appendEvent(
            context,
            sender = "1069000000000",
            body = "【菜鸟驿站】您的包裹已到阳光小区菜鸟驿站3号货架，凭取件码 8-2-3006 取件，18:00 前领取。",
            eventId = id,
        )
    }

    /** 桥接文件大小（字节）；文件不存在返回 0。 */
    fun inboxSize(context: Context): Long = inboxFile(context).takeIf { it.isFile }?.length() ?: 0L

    private fun rotateIfNeeded(inbox: File) {
        if (inbox.length() < MAX_FILE_BYTES) return
        val backup = File(inbox.parentFile, "inbox.jsonl.1")
        backup.delete()
        inbox.renameTo(backup)
    }
}
