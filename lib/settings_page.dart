import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'services/hive_service.dart';
import 'services/notification_service.dart';
import 'services/tab_prefs.dart';
import 'services/todo_overlay_bridge.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            MediaQuery.viewPaddingOf(context).bottom + 120,
          ),
          children: [
            Text(
              '设置',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const _SectionHeader(title: '外观'),
            const _SettingsCard(
              children: [_TabVisibilityEntry()],
            ),
            const SizedBox(height: 16),
            const _SectionHeader(title: '常驻面板'),
            const _SettingsCard(
              children: [
                _OngoingPanelSwitch(),
                _PanelStyleRow(),
                _BootStartSwitch(),
              ],
            ),
            const SizedBox(height: 16),
            const _SectionHeader(title: '到点提醒'),
            const _SettingsCard(
              children: [
                _ReminderAlertModeRow(),
              ],
            ),
            if (Platform.isAndroid) ...[
              const SizedBox(height: 16),
              const _SectionHeader(title: '通知悬浮窗'),
              const _SettingsCard(
                children: [
                  _NotificationQuickOverlaySwitch(),
                  _NotificationOverlayPermissionTile(),
                  _MoveTaskBackAfterOverlaySwitch(),
                ],
              ),
            ],
            const SizedBox(height: 16),
            const _SectionHeader(title: '反馈'),
            const _SettingsCard(
              children: [
                _CompleteCueSwitch(),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ========== 完成反馈 ==========

class _CompleteCueSwitch extends StatelessWidget {
  const _CompleteCueSwitch();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box>(
      valueListenable: HiveService.listenableSettings(
        const [NotificationService.kPrefCompleteCueEnabled],
      ),
      builder: (context, _, _) {
        final enabled = NotificationService.isCompleteCueEnabled;
        final scheme = Theme.of(context).colorScheme;
        return SwitchListTile.adaptive(
          value: enabled,
          title: const Text('完成提示音'),
          subtitle: Text(
            '勾选完成待办时播放一次系统点击音 + 轻震动',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          secondary: Icon(
            Icons.celebration_outlined,
            color: scheme.primary,
          ),
          onChanged: (v) async {
            await NotificationService.setCompleteCueEnabled(v);
            // 给一次即时预听
            if (v) await NotificationService.playCompleteCue();
          },
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        );
      },
    );
  }
}

// ========== 常驻面板：开关 ==========

class _OngoingPanelSwitch extends StatelessWidget {
  const _OngoingPanelSwitch();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box>(
      valueListenable: HiveService.listenableSettings(
        const [NotificationService.kPrefOngoingPanelEnabled],
      ),
      builder: (context, _, _) {
        final enabled = NotificationService.isOngoingPanelEnabled;
        final scheme = Theme.of(context).colorScheme;
        final subtitle = Platform.isAndroid
            ? '在系统通知栏常驻一个面板，显示待办进度、支持一键新建'
            : 'iOS 暂不支持常驻通知，开启后无效';

        return SwitchListTile.adaptive(
          value: enabled,
          title: const Text('开启常驻面板'),
          subtitle: Text(
            subtitle,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          secondary: Icon(
            Icons.push_pin_outlined,
            color: scheme.primary,
          ),
          onChanged: Platform.isAndroid
              ? (v) async {
                  await NotificationService.setOngoingPanelEnabled(v);
                }
              : null,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        );
      },
    );
  }
}

// ========== 常驻面板：样式 ==========

class _PanelStyleRow extends StatelessWidget {
  const _PanelStyleRow();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box>(
      valueListenable: HiveService.listenableSettings(
        const [NotificationService.kPrefPanelStyle],
      ),
      builder: (context, _, _) {
        final style = NotificationService.panelStyle;
        final enabled = NotificationService.isOngoingPanelEnabled &&
            Platform.isAndroid;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          enabled: enabled,
          leading: Icon(
            Icons.view_agenda_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          title: const Text('面板样式'),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: SegmentedButton<PanelStyleMode>(
              segments: PanelStyleMode.values
                  .map((m) => ButtonSegment<PanelStyleMode>(
                        value: m,
                        label: Text(m.label),
                      ))
                  .toList(),
              selected: {style},
              onSelectionChanged: enabled
                  ? (set) async {
                      if (set.isEmpty) return;
                      await NotificationService.setPanelStyle(set.first);
                    }
                  : null,
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        );
      },
    );
  }
}

// ========== 常驻面板：开机自启 ==========

class _BootStartSwitch extends StatelessWidget {
  const _BootStartSwitch();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box>(
      valueListenable: HiveService.listenableSettings(
        const [NotificationService.kPrefBootStartEnabled],
      ),
      builder: (context, _, _) {
        final enabled = NotificationService.isBootStartEnabled;
        final scheme = Theme.of(context).colorScheme;
        final available =
            Platform.isAndroid && NotificationService.isOngoingPanelEnabled;
        return SwitchListTile.adaptive(
          value: enabled,
          title: const Text('开机自启'),
          subtitle: Text(
            available
                ? '重启设备后自动在状态栏挂上常驻面板'
                : '仅 Android；且需先开启「常驻面板」',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          secondary: Icon(
            Icons.power_settings_new,
            color: scheme.primary,
          ),
          onChanged: available
              ? (v) async {
                  await NotificationService.setBootStartEnabled(v);
                }
              : null,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        );
      },
    );
  }
}

// ========== 通知悬浮窗（Android）==========

class _NotificationQuickOverlaySwitch extends StatelessWidget {
  const _NotificationQuickOverlaySwitch();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box>(
      valueListenable: HiveService.listenableSettings(
        const [kPrefNotificationQuickOverlay],
      ),
      builder: (context, _, _) {
        final enabled =
            HiveService.getSetting<bool>(kPrefNotificationQuickOverlay, false);
        final scheme = Theme.of(context).colorScheme;
        return SwitchListTile.adaptive(
          value: enabled,
          title: const Text('通知点待办时使用悬浮窗'),
          subtitle: Text(
            '需开启「显示在其他应用上层」权限；与列表里点行的弹窗内容一致',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          secondary: Icon(
            Icons.picture_in_picture_alt_outlined,
            color: scheme.primary,
          ),
          onChanged: (v) async {
            await HiveService.setSetting<bool>(kPrefNotificationQuickOverlay, v);
          },
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        );
      },
    );
  }
}

class _NotificationOverlayPermissionTile extends StatelessWidget {
  const _NotificationOverlayPermissionTile();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: Icon(Icons.layers_outlined, color: scheme.primary),
      title: const Text('开启悬浮窗权限'),
      subtitle: Text(
        '跳转到系统设置，允许本应用在其他应用上层显示',
        style: TextStyle(color: scheme.onSurfaceVariant),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        try {
          await FlutterOverlayWindow.requestPermission();
        } catch (_) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('无法打开权限页')),
          );
        }
      },
    );
  }
}

class _MoveTaskBackAfterOverlaySwitch extends StatelessWidget {
  const _MoveTaskBackAfterOverlaySwitch();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box>(
      valueListenable: HiveService.listenableSettings(
        const [kPrefMoveTaskBackAfterTodoOverlay],
      ),
      builder: (context, _, _) {
        final enabled = HiveService.getSetting<bool>(
          kPrefMoveTaskBackAfterTodoOverlay,
          true,
        );
        final scheme = Theme.of(context).colorScheme;
        return SwitchListTile.adaptive(
          value: enabled,
          title: const Text('悬浮窗出现后退回桌面'),
          subtitle: Text(
            '隐藏全屏应用界面；部分机型可能无效，应用仍在最近任务中可见',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          secondary: Icon(
            Icons.flip_to_back_outlined,
            color: scheme.primary,
          ),
          onChanged: (v) async {
            await HiveService.setSetting<bool>(
              kPrefMoveTaskBackAfterTodoOverlay,
              v,
            );
          },
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        );
      },
    );
  }
}

// ========== 到点提醒：响铃模式 ==========

class _ReminderAlertModeRow extends StatelessWidget {
  const _ReminderAlertModeRow();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box>(
      valueListenable: HiveService.listenableSettings(
        const [NotificationService.kPrefReminderAlertMode],
      ),
      builder: (context, _, _) {
        final mode = NotificationService.reminderAlertMode;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          leading: Icon(
            _iconFor(mode),
            color: Theme.of(context).colorScheme.primary,
          ),
          title: const Text('响铃模式'),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: SegmentedButton<ReminderAlertMode>(
              segments: ReminderAlertMode.values
                  .map((m) => ButtonSegment<ReminderAlertMode>(
                        value: m,
                        icon: Icon(_iconFor(m)),
                        label: Text(_shortLabel(m)),
                      ))
                  .toList(),
              selected: {mode},
              onSelectionChanged: (set) async {
                if (set.isEmpty) return;
                await NotificationService.setReminderAlertMode(set.first);
              },
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        );
      },
    );
  }

  static IconData _iconFor(ReminderAlertMode m) {
    switch (m) {
      case ReminderAlertMode.sound:
        return Icons.notifications_active_outlined;
      case ReminderAlertMode.vibrate:
        return Icons.vibration;
      case ReminderAlertMode.silent:
        return Icons.notifications_off_outlined;
    }
  }

  static String _shortLabel(ReminderAlertMode m) {
    switch (m) {
      case ReminderAlertMode.sound:
        return '响铃';
      case ReminderAlertMode.vibrate:
        return '震动';
      case ReminderAlertMode.silent:
        return '静音';
    }
  }
}

// ========== 标签页可见性：入口 ==========

class _TabVisibilityEntry extends StatelessWidget {
  const _TabVisibilityEntry();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<Box>(
      valueListenable: TabPrefs.listenable(),
      builder: (context, _, _) {
        final enabled = TabPrefs.enabledTabs();
        final summary = enabled.isEmpty
            ? '仅显示「设置」'
            : enabled.map((t) => t.label).join(' · ');
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          leading: Icon(Icons.tab_outlined, color: scheme.primary),
          title: const Text('标签页'),
          subtitle: Text(
            summary,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          trailing: const Icon(Icons.chevron_right, size: 20),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const TabVisibilityPage(),
              ),
            );
          },
        );
      },
    );
  }
}

/// 二级页：标签页显示偏好
class TabVisibilityPage extends StatelessWidget {
  const TabVisibilityPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: const Text('标签页'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ValueListenableBuilder<Box>(
          valueListenable: TabPrefs.listenable(),
          builder: (context, _, _) {
            final enabledCount = TabPrefs.enabledTabs().length;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                  child: Text(
                    '选择底部导航要显示的标签；「设置」始终保留。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ),
                _SettingsCard(
                  children: [
                    for (int i = 0; i < AppTab.values.length; i++) ...[
                      _TabSwitchTile(
                        tab: AppTab.values[i],
                        enabledCount: enabledCount,
                      ),
                      if (i < AppTab.values.length - 1)
                        Divider(
                          height: 1,
                          indent: 56,
                          color: scheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                    ],
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TabSwitchTile extends StatelessWidget {
  const _TabSwitchTile({required this.tab, required this.enabledCount});

  final AppTab tab;
  final int enabledCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isOn = TabPrefs.isEnabled(tab);
    final isLastOn = isOn && enabledCount <= 1;
    return SwitchListTile.adaptive(
      value: isOn,
      title: Text(tab.label),
      subtitle: Text(
        isLastOn ? '至少保留一个标签页' : '在底部导航中显示 ${tab.label}',
        style: TextStyle(color: scheme.onSurfaceVariant),
      ),
      secondary: Icon(tab.icon, color: scheme.primary),
      onChanged: isLastOn
          ? null
          : (v) async {
              await TabPrefs.setEnabled(tab, v);
            },
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
    );
  }
}

// ========== 公用分组 / 卡片 ==========

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Divider(
                height: 1,
                indent: 56,
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
          ],
        ],
      ),
    );
  }
}
