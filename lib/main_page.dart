import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'calendar_page.dart';
import 'schedule_page.dart';
import 'services/notification_service.dart';
import 'services/tab_prefs.dart';
import 'settings_page.dart';
import 'timeline_page.dart';
import 'todo_page.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  /// 当前选中 Tab 的枚举值；用枚举而不是下标，开关关闭后重建时仍能对得上。
  /// `null` 表示设置 Tab（它不进 [AppTab]）。
  AppTab? _currentTab = AppTab.timeline;
  bool _onSettings = false;

  StreamSubscription<String>? _notificationSub;

  @override
  void initState() {
    super.initState();
    // 冷启动通过通知拉起：先切到待办 tab，payload 保留给 TodoPage 消费
    if (NotificationService.hasPendingPayload) {
      _selectTab(AppTab.todo, silent: true);
    }
    _notificationSub = NotificationService.onTap.listen((_) {
      if (!mounted) return;
      setState(() => _selectTab(AppTab.todo, silent: true));
    });
  }

  @override
  void dispose() {
    _notificationSub?.cancel();
    super.dispose();
  }

  /// 设定当前 Tab；若传入的 Tab 被禁用则退到首个可用 Tab（或设置页）。
  void _selectTab(AppTab? tab, {bool silent = false}) {
    if (tab == null) {
      _currentTab = null;
      _onSettings = true;
    } else if (TabPrefs.isEnabled(tab)) {
      _currentTab = tab;
      _onSettings = false;
    } else {
      final enabled = TabPrefs.enabledTabs();
      if (enabled.isEmpty) {
        _currentTab = null;
        _onSettings = true;
      } else {
        _currentTab = enabled.first;
        _onSettings = false;
      }
    }
    if (!silent && mounted) setState(() {});
  }

  Widget _buildPage(AppTab tab) {
    switch (tab) {
      case AppTab.timeline:
        return const TimelinePage();
      case AppTab.calendar:
        return const CalendarPage();
      case AppTab.schedule:
        return const SchedulePage();
      case AppTab.todo:
        return const TodoPage();
    }
  }

  Widget _buildNavItem({
    required bool isSelected,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: double.infinity,
            padding: const EdgeInsets.only(top: 5),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isSelected ? Colors.blue : Colors.grey[600],
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: isSelected ? 11 : 10,
                    color: isSelected ? Colors.blue : Colors.grey[600],
                    height: 1.5,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box>(
      valueListenable: TabPrefs.listenable(),
      builder: (context, _, _) {
        final enabledTabs = TabPrefs.enabledTabs();

        // 若当前选中的 Tab 被关了，退到首个启用 Tab
        if (!_onSettings &&
            _currentTab != null &&
            !enabledTabs.contains(_currentTab)) {
          _currentTab = enabledTabs.isEmpty ? null : enabledTabs.first;
          _onSettings = _currentTab == null;
        }

        // IndexedStack 只保留"启用的"页面 + 设置页
        final stackChildren = <Widget>[
          for (final t in enabledTabs) _buildPage(t),
          const SettingsPage(),
        ];
        final stackIndex = _onSettings
            ? stackChildren.length - 1
            : (_currentTab == null
                ? 0
                : enabledTabs.indexOf(_currentTab!).clamp(
                      0,
                      stackChildren.length - 1,
                    ));

        return Scaffold(
          body: IndexedStack(
            index: stackIndex,
            children: stackChildren,
          ),
          bottomNavigationBar: Container(
            margin: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              13 + MediaQuery.viewPaddingOf(context).bottom,
            ),
            decoration: BoxDecoration(
              color:
                  Theme.of(context).bottomNavigationBarTheme.backgroundColor ??
                      Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.grey[300]!,
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: SizedBox(
                  height: 65,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      for (final t in enabledTabs)
                        _buildNavItem(
                          isSelected: !_onSettings && _currentTab == t,
                          icon: t.icon,
                          label: t.label,
                          onTap: () => _selectTab(t),
                        ),
                      _buildNavItem(
                        isSelected: _onSettings,
                        icon: Icons.settings,
                        label: '设置',
                        onTap: () => _selectTab(null),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 占位页面，保留作历史兼容。
class PlaceholderPage extends StatelessWidget {
  final String title;

  const PlaceholderPage({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.construction,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              '$title 功能开发中...',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
