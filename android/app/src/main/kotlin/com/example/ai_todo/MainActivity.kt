package com.example.ai_todo

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.media.ToneGenerator
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "ai_todo/native_prefs"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setBool" -> {
                        val key = call.argument<String>("key")
                        val value = call.argument<Boolean>("value")
                        if (key == null || value == null) {
                            result.error("ARG", "key/value missing", null)
                            return@setMethodCallHandler
                        }
                        NativePrefsStore.setBool(applicationContext, key, value)
                        result.success(null)
                    }
                    "clearNotification" -> {
                        val id = call.argument<Int>("id")
                        if (id != null) {
                            val nm = getSystemService(NotificationManager::class.java)
                            nm?.cancel(id)
                        }
                        result.success(null)
                    }
                    "playCompleteCue" -> {
                        playCompleteCue()
                        result.success(null)
                    }
                    "ensureChannels" -> {
                        ensureChannels()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * 播一次"完成待办"反馈音。
     *
     * 思路：优先复用用户系统里"默认通知音"（和微信/邮件收到通知时一样的声音），
     * 用 [Ringtone] 直接播放 —— 不创建任何通知，不会在状态栏弹横幅。
     * 这样既规避了 SystemSound/click 要求系统"触摸提示音"打开的限制，
     * 又保留通知音的识别度。
     *
     * 播放时长会截断到 ~1.2s，避免遇上长铃声把用户吵到。
     * 如果取不到铃声（极少见）退回 ToneGenerator 短 beep。
     */
    private var pendingRingtone: Ringtone? = null

    private fun playCompleteCue() {
        try {
            val ctx = applicationContext
            val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            val ringtone: Ringtone? = RingtoneManager.getRingtone(ctx, uri)
            if (ringtone != null) {
                ringtone.audioAttributes = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
                pendingRingtone?.stop()
                pendingRingtone = ringtone
                ringtone.play()
                window?.decorView?.postDelayed({
                    try {
                        if (ringtone.isPlaying) ringtone.stop()
                    } catch (_: Throwable) {}
                    if (pendingRingtone === ringtone) pendingRingtone = null
                }, 1200)
                return
            }
        } catch (_: Throwable) {
            // 取不到或播放失败则走 ToneGenerator 兜底
        }

        try {
            val tg = ToneGenerator(AudioManager.STREAM_NOTIFICATION, 80)
            tg.startTone(ToneGenerator.TONE_PROP_ACK, 150)
            window?.decorView?.postDelayed({
                try { tg.release() } catch (_: Throwable) {}
            }, 300)
        } catch (_: Throwable) {
            // 某些机型/静音策略下构造会失败，忽略
        }
    }

    /**
     * 原生注册通知渠道。相较 flutter_local_notifications 的 AndroidNotificationChannel：
     * - 显式指定 vibrationPattern（某些 OEM 仅认 pattern，不认 enableVibration=true）
     * - 显式 setLockscreenVisibility = PUBLIC（plugin 未暴露；MIUI 默认藏锁屏）
     * - 响铃模式绑定系统默认通知音 URI
     *
     * 响铃与「仅震动」共用 `todo_reminders_sound`（Dart 侧对仅震动发 `playSound:false`）。
     * 删除历史单渠道、试验 id、及已废弃的独立震动渠道 `todo_reminders_vibrate`。
     */
    private fun ensureChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(NotificationManager::class.java) ?: return

        val legacyIds = listOf(
            "todo_reminders",
            "todo_reminders_sound_v2",
            "todo_reminders_vibrate_v2",
            "todo_reminders_silent_v2",
            "todo_reminders_vibrate"
        )
        for (old in legacyIds) {
            try { nm.deleteNotificationChannel(old) } catch (_: Throwable) {}
        }

        // 略加长、多段脉冲，部分 ROM（尤其 MIUI）对过短 pattern 或「无声渠道」会默认关掉震动开关
        val vibrationPattern = longArrayOf(0, 280, 200, 280, 200, 280)
        val notifAudioAttrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val defaultSoundUri =
            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)

        val soundCh = NotificationChannel(
            "todo_reminders_sound",
            "待办提醒",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "到达提醒时间（应用内可设为响铃或仅震动）"
            enableVibration(true)
            setVibrationPattern(vibrationPattern)
            setSound(defaultSoundUri, notifAudioAttrs)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            setShowBadge(true)
            enableLights(true)
        }
        nm.createNotificationChannel(soundCh)

        val silentCh = NotificationChannel(
            "todo_reminders_silent",
            "待办提醒 · 静音",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "到点提醒（静音）"
            enableVibration(false)
            setSound(null, null)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            setShowBadge(true)
        }
        nm.createNotificationChannel(silentCh)

        // 常驻面板：静音低优先级，不上锁屏，不占 badge
        val panelCh = NotificationChannel(
            "todo_panel",
            "待办面板",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "状态栏常驻，显示待办进度与快速操作"
            enableVibration(false)
            setSound(null, null)
            lockscreenVisibility = Notification.VISIBILITY_SECRET
            setShowBadge(false)
        }
        nm.createNotificationChannel(panelCh)
    }
}
