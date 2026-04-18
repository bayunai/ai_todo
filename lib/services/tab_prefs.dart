import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import 'hive_service.dart';

/// 底部导航上可以被用户隐藏的 Tab。设置 Tab 始终保留，不在此枚举。
enum AppTab {
  timeline('tab_timeline_enabled', '时间线', Icons.view_timeline_outlined),
  calendar('tab_calendar_enabled', '日历', Icons.calendar_today),
  schedule('tab_schedule_enabled', '班表', Icons.schedule),
  todo('tab_todo_enabled', '待办', Icons.checklist);

  final String prefKey;
  final String label;
  final IconData icon;
  const AppTab(this.prefKey, this.label, this.icon);
}

/// 标签显示偏好的读写层。
class TabPrefs {
  TabPrefs._();

  /// 默认全部启用；读旧数据没写过则回 [true]。
  static bool isEnabled(AppTab tab) =>
      HiveService.getSetting<bool>(tab.prefKey, true);

  static Future<void> setEnabled(AppTab tab, bool value) =>
      HiveService.setSetting<bool>(tab.prefKey, value);

  /// 当前启用的 Tab 列表，保持枚举顺序。
  static List<AppTab> enabledTabs() =>
      AppTab.values.where(isEnabled).toList(growable: false);

  /// Settings 页监听使用。变更任何一个 Tab 开关都会触发。
  static ValueListenable<Box> listenable() => HiveService.listenableSettings(
        AppTab.values.map((t) => t.prefKey).toList(),
      );
}
