package com.example.ai_todo

import android.app.NotificationManager
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.media.ToneGenerator
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
}
