package com.example.ai_todo

import android.content.Context
import android.content.SharedPreferences

/**
 * 轻量 SharedPreferences 封装：Flutter 和 BootReceiver 共用同一份键值对，
 * 用于在 Flutter 引擎未启动时（设备开机广播）也能读取用户开关。
 */
object NativePrefsStore {
    const val PREFS_NAME = "ai_todo_native_prefs"

    const val KEY_PANEL_ENABLED = "panel_enabled"
    const val KEY_BOOT_START_ENABLED = "boot_start_enabled"

    const val PANEL_CHANNEL_ID = "todo_panel"
    const val PANEL_CHANNEL_NAME = "待办面板"
    const val PANEL_CHANNEL_DESC = "状态栏常驻，显示待办进度与快速操作"
    const val PANEL_NOTIFICATION_ID = 20260418

    fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun setBool(context: Context, key: String, value: Boolean) {
        prefs(context).edit().putBoolean(key, value).apply()
    }

    fun getBool(context: Context, key: String, default: Boolean): Boolean =
        prefs(context).getBoolean(key, default)
}
