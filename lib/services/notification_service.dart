import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/todo_model.dart';
import 'hive_service.dart';

/// 后台点击回调必须是顶层或静态函数。
/// 这里只做最轻工作：把 payload 写入进程间可共享的 stream/pending 字段。
@pragma('vm:entry-point')
void _onBackgroundNotificationResponse(NotificationResponse response) {
  final payload = response.payload;
  if (payload == null || payload.isEmpty) return;
  NotificationService._dispatch(payload);
}

class NotificationService {
  NotificationService._();

  static const String _channelId = 'todo_reminders';
  static const String _channelName = '待办提醒';
  static const String _channelDesc = '到达提醒时间时弹出待办通知';

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static final StreamController<String> _tapCtrl =
      StreamController<String>.broadcast();
  static String? _pendingPayload;
  static bool _initialized = false;

  /// 点击通知后的 payload（todo.id）广播流；前台/后台/冷启动都从此出。
  static Stream<String> get onTap => _tapCtrl.stream;

  /// 冷启动后，UI 消费一次；取出即清空。
  static String? consumePendingPayload() {
    final p = _pendingPayload;
    _pendingPayload = null;
    return p;
  }

  /// 冷启动后仅查看是否有待处理 payload（不清空）。用于 MainPage 切换 tab 而把实际
  /// payload 留给 TodoPage 去 [consumePendingPayload]。
  static bool get hasPendingPayload => _pendingPayload != null;

  /// 内部：统一写 pending + broadcast
  static void _dispatch(String payload) {
    _pendingPayload = payload;
    if (!_tapCtrl.isClosed) {
      _tapCtrl.add(payload);
    }
  }

  static Future<void> init() async {
    if (_initialized) return;

    tzdata.initializeTimeZones();
    try {
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      // 获取失败时保留 UTC，不抛出
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
      macOS: darwinInit,
    );

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          _dispatch(payload);
        }
      },
      onDidReceiveBackgroundNotificationResponse:
          _onBackgroundNotificationResponse,
    );

    // 确保 Android 通知渠道存在
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDesc,
          importance: Importance.high,
          enableVibration: true,
        ),
      );
    }

    // 冷启动由通知拉起时，取 payload 缓存给 UI 消费
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp == true) {
      final payload = details!.notificationResponse?.payload;
      if (payload != null && payload.isNotEmpty) {
        _pendingPayload = payload;
      }
    }

    _initialized = true;
  }

  /// 请求通知 + 精确闹钟权限。任一关键权限未授予则返回 false，由 UI 决定提示方式。
  static Future<bool> ensurePermissions() async {
    if (!_initialized) {
      await init();
    }

    if (!(Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) {
      return true;
    }

    if (Platform.isIOS || Platform.isMacOS) {
      final iOS = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final mac = _plugin.resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin>();
      final granted = await iOS?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          await mac?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          true;
      return granted;
    }

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;

    final notifGranted = await android.requestNotificationsPermission() ?? true;
    // 精确闹钟在 Android 12+ 需要单独授予；插件会打开系统设置让用户授权
    final exactGranted =
        await android.requestExactAlarmsPermission() ?? true;
    return notifGranted && exactGranted;
  }

  /// 以 [todo.id] 的 hashCode 作为稳定的 notification id。
  static int _idFor(String todoId) => todoId.hashCode & 0x7fffffff;

  /// 先取消旧调度，再按当前状态重新安排：
  /// - 已完成 / 无提醒 / 提醒时间不在未来 → 仅取消
  static Future<void> scheduleForTodo(TodoModel todo) async {
    if (!_initialized) return;
    final id = _idFor(todo.id);
    await _plugin.cancel(id);

    final when = todo.remindAt;
    if (todo.done || when == null) return;
    final scheduled = tz.TZDateTime.from(when, tz.local);
    if (scheduled.isBefore(tz.TZDateTime.now(tz.local))) return;

    final body = todo.note.isNotEmpty ? todo.note : '到点啦，记得处理这条待办';
    try {
      await _plugin.zonedSchedule(
        id,
        todo.title.isEmpty ? '待办提醒' : todo.title,
        body,
        scheduled,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDesc,
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.reminder,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: todo.id,
      );
    } catch (e, st) {
      // 未授权 SCHEDULE_EXACT_ALARM 等情况不应 crash app；由 UI 的 ensurePermissions 提示
      debugPrint('[NotificationService] schedule failed: $e\n$st');
    }
  }

  static Future<void> cancelForTodo(String id) async {
    if (!_initialized) return;
    await _plugin.cancel(_idFor(id));
  }

  /// 启动时兜底：升级/重装/时区变更/重启后，根据 Hive 中所有待办重建调度。
  static Future<void> rescheduleAllFromHive() async {
    if (!_initialized) return;
    await _plugin.cancelAll();
    final todos = HiveService.getAllTodos();
    for (final t in todos) {
      if (!t.done && t.remindAt != null) {
        await scheduleForTodo(t);
      }
    }
  }
}
