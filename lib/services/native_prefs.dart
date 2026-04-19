import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// 把若干设置项同步到 Android 原生 SharedPreferences，
/// 供启动时（boot 广播）没有 Flutter 引擎也能读取到的场景使用。
///
/// 仅需要在 Android 上工作；iOS/macOS 直接 no-op。
class NativePrefs {
  NativePrefs._();

  static const MethodChannel _channel = MethodChannel('ai_todo/native_prefs');

  static const String kPanelEnabled = 'panel_enabled';
  static const String kBootStartEnabled = 'boot_start_enabled';

  static Future<void> setBool(String key, bool value) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('setBool', {
        'key': key,
        'value': value,
      });
    } catch (_) {
      // 原生通道不可用时静默：不要让设置写入失败拖垮 UI
    }
  }

  /// 播一次短促的完成提示音（ToneGenerator ACK），仅 Android 有效。
  /// 不受"触摸提示音"系统开关影响；跟随通知/媒体音量。
  static Future<void> playCompleteCue() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('playCompleteCue');
    } catch (_) {
      // 渠道异常时静默
    }
  }

  /// 原生注册 / 刷新通知渠道。相较 flutter_local_notifications：
  /// 会显式设置 vibrationPattern、lockscreenVisibility、默认通知音 URI，
  /// 规避 MIUI 等 ROM 对新渠道默认降级的坑。仅 Android 有效。
  static Future<void> ensureChannels() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('ensureChannels');
    } catch (_) {
      // 渠道异常时静默
    }
  }

  /// 将主任务栈移到后台（仅 Android）。用于通知悬浮窗出现后减轻「全屏进应用」观感。
  static Future<void> moveTaskToBackIfAndroid() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('moveTaskToBack');
    } catch (_) {
      // 部分 ROM 或时机下会失败，静默即可
    }
  }
}
