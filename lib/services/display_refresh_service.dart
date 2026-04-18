import 'dart:io' show Platform;

import 'package:flutter_displaymode/flutter_displaymode.dart';

/// 在 Android 上向系统请求当前分辨率下的最高刷新率（由系统决定是否采纳）。
Future<void> preferHighRefreshRateIfSupported() async {
  if (!Platform.isAndroid) return;
  try {
    await FlutterDisplayMode.setHighRefreshRate();
  } catch (_) {
    // 模拟器、部分 ROM 或未开放 API 时忽略
  }
}
