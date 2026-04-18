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
}
