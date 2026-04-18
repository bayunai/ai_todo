import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
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
  final actionId = response.actionId;
  if (actionId == NotificationService.kPanelAddActionId) {
    NotificationService._dispatch(NotificationService.panelAddPayload);
    return;
  }
  final payload = response.payload;
  if (payload == null || payload.isEmpty) return;
  NotificationService._dispatch(payload);
}

class NotificationService {
  NotificationService._();

  static const String _channelId = 'todo_reminders';
  static const String _channelName = '待办提醒';
  static const String _channelDesc = '到达提醒时间时弹出待办通知';

  // 常驻面板（状态栏）：Android 专用，静音低优先级，不可滑除
  static const String _panelChannelId = 'todo_panel';
  static const String _panelChannelName = '待办面板';
  static const String _panelChannelDesc = '状态栏常驻，显示待办进度与快速操作';
  static const int _panelId = 2026_04_18;

  /// 面板点击体本身对应的 payload（只切 Tab，不做额外动作）
  static const String panelOpenPayload = 'panel:open';

  /// 「添加」action 对应的 payload
  static const String panelAddPayload = 'panel:add';

  /// 「添加」action id，供后台回调识别
  static const String kPanelAddActionId = 'panel_add';

  // 19.x：插件实例必须在 Flutter 绑定初始化之后构造，避免
  // FlutterLocalNotificationsPlatform._instance 未注册导致 LateInitializationError。
  static FlutterLocalNotificationsPlugin? _pluginInstance;
  static FlutterLocalNotificationsPlugin get _plugin {
    final p = _pluginInstance;
    if (p == null) {
      throw StateError('NotificationService.init() must be called first');
    }
    return p;
  }

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

    // 19.x：确保 Flutter 引擎已就绪后再创建插件实例
    WidgetsFlutterBinding.ensureInitialized();
    _pluginInstance ??= FlutterLocalNotificationsPlugin();

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
        final actionId = response.actionId;
        if (actionId == kPanelAddActionId) {
          _dispatch(panelAddPayload);
          return;
        }
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
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          _panelChannelId,
          _panelChannelName,
          description: _panelChannelDesc,
          importance: Importance.low,
          playSound: false,
          enableVibration: false,
          showBadge: false,
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
  /// - 已完成 / 无提醒 → 仅取消
  /// - 单次且提醒时间不在未来 → 仅取消
  /// - 重复规则非 none → 首次时刻 + matchDateTimeComponents 按周期复发
  static Future<void> scheduleForTodo(TodoModel todo) async {
    if (!_initialized) return;
    final id = _idFor(todo.id);
    await _plugin.cancel(id);

    final raw = todo.remindAt;
    if (todo.done || raw == null) return;

    // 全天提醒：时=0 时默认推到当天 09:00
    DateTime when = raw;
    if (todo.remindIsAllDay && when.hour == 0 && when.minute == 0) {
      when = DateTime(when.year, when.month, when.day, 9, 0);
    }

    var scheduled = tz.TZDateTime.from(when, tz.local);
    final now = tz.TZDateTime.now(tz.local);

    final repeat = todo.remindRepeatRule;
    final isRepeating = repeat != TodoRepeat.none;

    if (isRepeating) {
      // 历史时刻：推到下一个匹配时刻，避免 zonedSchedule 报 "past time"
      scheduled = _rollForward(scheduled, repeat, now);
    } else {
      if (scheduled.isBefore(now)) return;
    }

    final match = _matchComponentsOf(repeat);

    final body = todo.note.isNotEmpty ? todo.note : '到点啦，记得处理这条待办';
    final androidMode = isRepeating
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.alarmClock;

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
        androidScheduleMode: androidMode,
        matchDateTimeComponents: match,
        payload: todo.id,
      );
    } catch (e, st) {
      // 未授权 SCHEDULE_EXACT_ALARM 等情况不应 crash app；由 UI 的 ensurePermissions 提示
      debugPrint('[NotificationService] schedule failed: $e\n$st');
    }
  }

  /// 将重复规则映射为 plugin 匹配规则。
  static DateTimeComponents? _matchComponentsOf(int rule) {
    switch (rule) {
      case TodoRepeat.daily:
        return DateTimeComponents.time;
      case TodoRepeat.weekly:
        return DateTimeComponents.dayOfWeekAndTime;
      case TodoRepeat.monthly:
        return DateTimeComponents.dayOfMonthAndTime;
      case TodoRepeat.yearly:
        return DateTimeComponents.dateAndTime;
      case TodoRepeat.none:
      default:
        return null;
    }
  }

  /// 重复规则下，把过去时刻推到下一个匹配的未来时刻。
  static tz.TZDateTime _rollForward(
    tz.TZDateTime base,
    int rule,
    tz.TZDateTime now,
  ) {
    var t = base;
    switch (rule) {
      case TodoRepeat.daily:
        while (!t.isAfter(now)) {
          t = t.add(const Duration(days: 1));
        }
        return t;
      case TodoRepeat.weekly:
        while (!t.isAfter(now)) {
          t = t.add(const Duration(days: 7));
        }
        return t;
      case TodoRepeat.monthly:
        while (!t.isAfter(now)) {
          t = tz.TZDateTime(
              tz.local, t.year, t.month + 1, t.day, t.hour, t.minute);
        }
        return t;
      case TodoRepeat.yearly:
        while (!t.isAfter(now)) {
          t = tz.TZDateTime(
              tz.local, t.year + 1, t.month, t.day, t.hour, t.minute);
        }
        return t;
      default:
        return t;
    }
  }

  static Future<void> cancelForTodo(String id) async {
    if (!_initialized) return;
    await _plugin.cancel(_idFor(id));
  }

  /// 启动时兜底：升级/重装/时区变更/重启后，根据 Hive 中所有待办重建调度。
  /// 注意：保留常驻面板通知，只取消"到点提醒"类通知。
  static Future<void> rescheduleAllFromHive() async {
    if (!_initialized) return;
    final pending = await _plugin.pendingNotificationRequests();
    for (final p in pending) {
      if (p.id != _panelId) {
        await _plugin.cancel(p.id);
      }
    }
    final todos = HiveService.getAllTodos();
    for (final t in todos) {
      if (!t.done && t.remindAt != null) {
        await scheduleForTodo(t);
      }
    }
  }

  // ========= 常驻面板 =========

  /// 用户偏好：常驻面板开关，默认开启
  static const String kPrefOngoingPanelEnabled = 'ongoing_panel_enabled';

  static VoidCallback? _panelBoxListener;

  static bool get isOngoingPanelEnabled =>
      HiveService.getSetting<bool>(kPrefOngoingPanelEnabled, true);

  /// 启动常驻面板：初次 show + 挂载 Hive 变更监听，
  /// 每次待办 box 变更（增删改、勾选完成等）都会刷新展示。
  /// 若用户关闭了开关则直接跳过。
  static Future<void> startOngoingPanel() async {
    if (!Platform.isAndroid) return;
    if (!isOngoingPanelEnabled) return;
    if (!_initialized) await init();

    await refreshOngoingPanel();

    _panelBoxListener ??= () {
      // 监听器是同步回调，用 unawaited 派发异步刷新
      // ignore: discarded_futures
      refreshOngoingPanel();
    };
    HiveService.listenableTodos().addListener(_panelBoxListener!);
  }

  /// 关闭常驻面板并停止监听。
  static Future<void> stopOngoingPanel() async {
    if (_panelBoxListener != null) {
      HiveService.listenableTodos().removeListener(_panelBoxListener!);
      _panelBoxListener = null;
    }
    if (!_initialized) return;
    try {
      await _plugin.cancel(_panelId);
    } catch (_) {}
  }

  /// 设置开关：持久化 + 立刻启/停面板。
  static Future<void> setOngoingPanelEnabled(bool enabled) async {
    await HiveService.setSetting<bool>(kPrefOngoingPanelEnabled, enabled);
    if (enabled) {
      await startOngoingPanel();
    } else {
      await stopOngoingPanel();
    }
  }

  /// 根据当前 Hive 中的待办实时生成面板文案并刷新。
  static Future<void> refreshOngoingPanel() async {
    if (!Platform.isAndroid || !_initialized) return;

    final todos = HiveService.getAllTodos();
    var total = todos.length;
    var done = 0;
    var overdue = 0;
    for (final t in todos) {
      if (t.done) {
        done++;
      } else if (t.isOverdue) {
        overdue++;
      }
    }
    final pending = total - done;

    final title = total == 0 ? '待办' : '待办  $done / $total';
    final String body;
    if (total == 0) {
      body = '点「添加」创建第一条待办';
    } else if (overdue > 0) {
      body = '进行中 $pending · 逾期 $overdue';
    } else if (pending == 0) {
      body = '全部搞定 🎉';
    } else {
      body = '还有 $pending 条进行中';
    }

    final details = AndroidNotificationDetails(
      _panelChannelId,
      _panelChannelName,
      channelDescription: _panelChannelDesc,
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      playSound: false,
      enableVibration: false,
      onlyAlertOnce: true,
      showWhen: false,
      category: AndroidNotificationCategory.status,
      visibility: NotificationVisibility.public,
      actions: const <AndroidNotificationAction>[
        AndroidNotificationAction(
          kPanelAddActionId,
          '添加',
          showsUserInterface: true,
          cancelNotification: false,
        ),
      ],
    );

    try {
      await _plugin.show(
        _panelId,
        title,
        body,
        NotificationDetails(android: details),
        payload: panelOpenPayload,
      );
    } catch (e, st) {
      debugPrint('[NotificationService] panel show failed: $e\n$st');
    }
  }
}
