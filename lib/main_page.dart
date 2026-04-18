import 'dart:async';

import 'package:flutter/material.dart';
import 'calendar_page.dart';
import 'schedule_page.dart';
import 'services/notification_service.dart';
import 'settings_page.dart';
import 'todo_page.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _currentIndex = 0;
  StreamSubscription<String>? _notificationSub;

  final List<Widget> _pages = [
    const CalendarPage(),
    const SchedulePage(),
    const TodoPage(),
    const SettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    // 冷启动通过通知拉起：先切到待办 tab，payload 保留给 TodoPage 消费
    if (NotificationService.hasPendingPayload) {
      _currentIndex = 2;
    }
    _notificationSub = NotificationService.onTap.listen((_) {
      if (!mounted) return;
      setState(() => _currentIndex = 2);
    });
  }

  @override
  void dispose() {
    _notificationSub?.cancel();
    super.dispose();
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (index >= 0 && index < _pages.length) {
              setState(() {
                _currentIndex = index;
              });
            }
          },
          child: Container(
            height: double.infinity,
            padding: const EdgeInsets.only(top: 5), // 向上移动3像素（从10改为7）
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
    // 确保索引在有效范围内
    final safeIndex = _pages.isEmpty 
        ? null 
        : _currentIndex.clamp(0, _pages.length - 1);
    
    return Scaffold(
      body: _pages.isEmpty
          ? const Center(child: Text('没有可用的页面'))
          : IndexedStack(
              index: safeIndex,
              children: _pages,
            ),
      bottomNavigationBar: Container(
        margin: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          13 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).bottomNavigationBarTheme.backgroundColor ??
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
              height: 65, // 调整到65
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildNavItem(0, Icons.calendar_today, '日历'),
                  _buildNavItem(1, Icons.schedule, '班表'),
                  _buildNavItem(2, Icons.checklist, '待办'),
                  _buildNavItem(3, Icons.settings, '设置'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// 占位页面，用于其他标签
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

