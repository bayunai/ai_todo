package com.example.ai_todo

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat

/**
 * 监听开机 / 应用升级广播：若用户开启了「开机自启」且「常驻面板」开关同时为真，
 * 则在 Flutter 进程还未运行的情况下先挂一条占位常驻通知，用户点击即可启动 app，
 * Flutter 启动后会以最新数据刷新同 id 的通知。
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in BOOT_ACTIONS) return

        val ctx = context.applicationContext
        val bootEnabled = NativePrefsStore.getBool(
            ctx, NativePrefsStore.KEY_BOOT_START_ENABLED, false
        )
        val panelEnabled = NativePrefsStore.getBool(
            ctx, NativePrefsStore.KEY_PANEL_ENABLED, true
        )
        if (!bootEnabled || !panelEnabled) return

        showPlaceholderPanel(ctx)
    }

    private fun showPlaceholderPanel(ctx: Context) {
        val nm = ctx.getSystemService(NotificationManager::class.java) ?: return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val existing = nm.getNotificationChannel(NativePrefsStore.PANEL_CHANNEL_ID)
            if (existing == null) {
                val channel = NotificationChannel(
                    NativePrefsStore.PANEL_CHANNEL_ID,
                    NativePrefsStore.PANEL_CHANNEL_NAME,
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = NativePrefsStore.PANEL_CHANNEL_DESC
                    setShowBadge(false)
                    enableVibration(false)
                    setSound(null, null)
                }
                nm.createNotificationChannel(channel)
            }
        }

        val launch = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)
            ?.apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
        val pi = launch?.let {
            PendingIntent.getActivity(
                ctx, 0, it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        val notification = NotificationCompat.Builder(ctx, NativePrefsStore.PANEL_CHANNEL_ID)
            .setSmallIcon(ctx.applicationInfo.icon)
            .setContentTitle("待办")
            .setContentText("点击打开应用")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(pi)
            .build()

        nm.notify(NativePrefsStore.PANEL_NOTIFICATION_ID, notification)
    }

    companion object {
        private val BOOT_ACTIONS = setOf(
            Intent.ACTION_BOOT_COMPLETED,
            "android.intent.action.QUICKBOOT_POWERON",
            "com.htc.intent.action.QUICKBOOT_POWERON",
            Intent.ACTION_MY_PACKAGE_REPLACED
        )
    }
}
