package com.mofox.android.keepalive

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootCompletedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in bootActions) return
        if (!MoFoxForegroundService.isKeepaliveEnabled(context)) return

        context.startForegroundService(Intent(context, MoFoxForegroundService::class.java))
    }

    private companion object {
        val bootActions = setOf(
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_LOCKED_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
        )
    }
}