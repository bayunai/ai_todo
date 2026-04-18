import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'services/hive_service.dart';
import 'services/notification_service.dart';

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
            const SizedBox(height: 16),
            _SectionHeader(title: '通知'),
            _SettingsCard(
              children: [
                _OngoingPanelSwitch(),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ========== 常驻面板开关 ==========

class _OngoingPanelSwitch extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // 关键：用 Hive 的 settings box + 监听指定 key，开关状态跨页面始终同步
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
          title: const Text('常驻状态栏'),
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
