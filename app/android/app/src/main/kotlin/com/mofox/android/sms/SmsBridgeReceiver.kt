package com.mofox.android.sms

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.util.Log

/**
 * 系统短信广播接收器（SMS_RECEIVED）。
 *
 * 收到短信后按桥接协议追加写入 rootfs，由 proot 内的 mofox_sms_bridge
 * 插件消费。这里只做轻量转发（拼 PDU + 写文件），不做内容解析——
 * 识别与通知决策全部在 Bot 插件侧完成，且受用户开关控制。
 */
class SmsBridgeReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "SmsBridgeReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return

        try {
            val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
            // 同一条 intent 里的多个 SmsMessage 是长短信的分段，按序拼接为一条事件
            val sender = messages.firstOrNull()?.originatingAddress.orEmpty()
            val body = StringBuilder().apply {
                for (message in messages) {
                    message?.displayMessageBody?.let { append(it) }
                }
            }.toString()

            val eventId = "${System.currentTimeMillis()}-${(sender + body).hashCode()}"
            val written = SmsBridge.appendEvent(context, sender, body, eventId)
            Log.d(TAG, "SMS received: sender=$sender len=${body.length} written=$written")
        } catch (e: Exception) {
            // 短信广播处理绝不能抛异常（系统有序广播，崩溃会影响后续接收者）
            Log.e(TAG, "处理短信广播失败", e)
        }
    }
}
