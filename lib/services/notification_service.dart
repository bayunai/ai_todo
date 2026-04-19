import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/todo_model.dart';
import 'hive_service.dart';
import 'native_prefs.dart';

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

/// 到点提醒的响铃模式。每种模式对应一个独立的通知渠道，
/// 因为 Android 通知渠道的 importance/声音/震动创建后不可修改，
/// 切换模式时通过切换渠道生效。
enum ReminderAlertMode {
  sound(
    id: 'todo_reminders_sound',
    label: '铃声 + 震动',
    persistValue: 0,
  ),
  /// 与 [sound] 共用 `todo_reminders_sound` 渠道：MIUI/HyperOS 对独立「仅震动」渠道
  /// 常错误地把系统「震动」登记为关；共用已正确登记的渠道，靠 [scheduleForTodo] 里 `playSound: false` 静音。
  vibrate(
    id: 'todo_reminders_sound',
    label: '仅震动',
    persistValue: 1,
  ),
  silent(
    id: 'todo_reminders_silent',
    label: '静音',
    persistValue: 2,
  );

  const ReminderAlertMode({
    required this.id,
    required this.label,
    required this.persistValue,
  });

  final String id;
  final String label;
  final int persistValue;

  static ReminderAlertMode fromPersist(int v) {
    for (final m in ReminderAlertMode.values) {
      if (m.persistValue == v) return m;
    }
    return ReminderAlertMode.sound;
  }
}

/// 常驻面板的展示样式。
enum PanelStyleMode {
  compact(label: '简洁', persistValue: 0),
  detailed(label: '详细', persistValue: 1);

  const PanelStyleMode({required this.label, required this.persistValue});
  final String label;
  final int persistValue;

  static PanelStyleMode fromPersist(int v) {
    for (final m in PanelStyleMode.values) {
      if (m.persistValue == v) return m;
    }
    return PanelStyleMode.compact;
  }
}

class NotificationService {
  NotificationService._();

  /// 与原生 `MainActivity.ensureChannels` 中 pattern 一致；必须非空。
  /// 插件在 pattern 为空时不会调用 NotificationCompat.Builder.setVibrate，部分 ROM 上会导致「仅震动」不生效。
  static final Int64List _reminderVibrationPattern =
      Int64List.fromList([0, 280, 200, 280, 200, 280]);

  // 提醒渠道的人类可读名/描述：AndroidNotificationDetails 里作为 fallback 传入；
  // 实际 id 与属性均由原生侧 `NativePrefs.ensureChannels()` 预建。
  static const String _channelName = '待办提醒';
  static const String _channelDesc = '到达提醒时间时弹出待办通知';

  // 常驻面板（状态栏）：Android 专用，静音低优先级，不可滑除
  static const String _panelChannelId = 'todo_panel';
  static const String _panelChannelName = '待办面板';
  static const String _panelChannelDesc = '状态栏常驻，显示待办进度与快速操作';
  static const int _panelId = 20260418;

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

  /// Android：点「待办提醒」通知时，在发 [onTap] 之前先执行（例如弹出悬浮窗）。
  /// 由 [main.dart] 注册，避免 [notification_service] 依赖悬浮窗模块产生循环 import。
  static Future<void> Function(String todoId)? androidTodoTapPreprocessor;

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

  /// 查看当前 pending（不清空），供路由/Tab 判断等使用。
  static String? peekPendingPayload() => _pendingPayload;

  /// 内部：统一写 pending + broadcast
  static void _dispatch(String payload) {
    _pendingPayload = payload;
    if (!_tapCtrl.isClosed) {
      _tapCtrl.add(payload);
    }
  }

  /// 主线程：先 [androidTodoTapPreprocessor]（若已注册），再发 [onTap]。
  static Future<void> _emitTodoTapWithPreprocessor(String payload) async {
    _pendingPayload = payload;
    final pre = androidTodoTapPreprocessor;
    if (pre != null) {
      await pre(payload);
    }
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
        if (payload == null || payload.isEmpty) return;

        if (Platform.isAndroid &&
            payload != panelOpenPayload &&
            payload != panelAddPayload &&
            HiveService.getTodoById(payload) != null) {
          unawaited(_emitTodoTapWithPreprocessor(payload));
          return;
        }
        _dispatch(payload);
      },
      onDidReceiveBackgroundNotificationResponse:
          _onBackgroundNotificationResponse,
    );

    // 通知渠道走原生注册：显式设置 vibrationPattern / lockscreenVisibility /
    // 默认通知音 URI 等 flutter_local_notifications 未暴露的属性，
    // 规避 MIUI / HyperOS 对新渠道默认降级（震动关、锁屏隐藏、悬浮关）。
    // 仅 Android 生效；iOS/macOS 走 Darwin initialization。
    await NativePrefs.ensureChannels();

    // 把当前 pref 值同步到原生 SharedPreferences，供 BootReceiver 读取
    await NativePrefs.setBool(
      NativePrefs.kPanelEnabled,
      isOngoingPanelEnabled,
    );
    await NativePrefs.setBool(
      NativePrefs.kBootStartEnabled,
      isBootStartEnabled,
    );

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
    if (todo.done || raw == null || !todo.remindNotifyEnabled) return;

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

    final mode = reminderAlertMode;
    final androidDetails = AndroidNotificationDetails(
      mode.id,
      _channelName,
      channelDescription: _channelDesc,
      importance: mode == ReminderAlertMode.silent
          ? Importance.low
          : Importance.high,
      priority: mode == ReminderAlertMode.silent
          ? Priority.low
          : Priority.high,
      category: AndroidNotificationCategory.reminder,
      playSound: mode == ReminderAlertMode.sound,
      enableVibration: mode != ReminderAlertMode.silent,
      vibrationPattern: mode == ReminderAlertMode.silent
          ? null
          : _reminderVibrationPattern,
    );

    try {
      await _plugin.zonedSchedule(
        id,
        todo.title.isEmpty ? '待办提醒' : todo.title,
        body,
        scheduled,
        NotificationDetails(
          android: androidDetails,
          iOS: const DarwinNotificationDetails(
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

  // ========= 偏好 keys =========

  /// 常驻面板开关，默认开启
  static const String kPrefOngoingPanelEnabled = 'ongoing_panel_enabled';

  /// 面板样式（0=简洁, 1=详细）
  static const String kPrefPanelStyle = 'panel_style';

  /// 到点提醒响铃模式（0=声音, 1=震动, 2=静音）
  static const String kPrefReminderAlertMode = 'reminder_alert_mode';

  /// 开机自启面板，默认关闭
  static const String kPrefBootStartEnabled = 'boot_start_enabled';

  /// 完成待办音效 + 触感，默认开启
  static const String kPrefCompleteCueEnabled = 'complete_cue_enabled';

  static bool get isOngoingPanelEnabled =>
      HiveService.getSetting<bool>(kPrefOngoingPanelEnabled, true);

  static PanelStyleMode get panelStyle => PanelStyleMode.fromPersist(
        HiveService.getSetting<int>(
          kPrefPanelStyle,
          PanelStyleMode.compact.persistValue,
        ),
      );

  static ReminderAlertMode get reminderAlertMode =>
      ReminderAlertMode.fromPersist(
        HiveService.getSetting<int>(
          kPrefReminderAlertMode,
          ReminderAlertMode.sound.persistValue,
        ),
      );

  static bool get isBootStartEnabled =>
      HiveService.getSetting<bool>(kPrefBootStartEnabled, false);

  static bool get isCompleteCueEnabled =>
      HiveService.getSetting<bool>(kPrefCompleteCueEnabled, true);

  /// 勾选"完成待办"时播放的反馈：震动 + 短促 beep。
  /// - Android 走原生 ToneGenerator（不受"触摸提示音"系统开关影响）
  /// - 其它平台退回 Flutter 内建 `SystemSound.click`
  /// 用户关闭开关后直接 no-op。
  static Future<void> playCompleteCue() async {
    if (!isCompleteCueEnabled) return;
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {}
    if (Platform.isAndroid) {
      await NativePrefs.playCompleteCue();
    } else {
      try {
        await SystemSound.play(SystemSoundType.click);
      } catch (_) {}
    }
  }

  /// 切换"完成音效"开关并持久化。
  static Future<void> setCompleteCueEnabled(bool enabled) async {
    await HiveService.setSetting<bool>(kPrefCompleteCueEnabled, enabled);
  }

  // ========= 常驻面板 =========

  static VoidCallback? _panelBoxListener;

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

  /// 设置开关：持久化 + 立刻启/停面板 + 同步原生 SharedPreferences。
  static Future<void> setOngoingPanelEnabled(bool enabled) async {
    await HiveService.setSetting<bool>(kPrefOngoingPanelEnabled, enabled);
    await NativePrefs.setBool(NativePrefs.kPanelEnabled, enabled);
    if (enabled) {
      await startOngoingPanel();
    } else {
      await stopOngoingPanel();
    }
  }

  /// 设置面板样式：持久化 + 立刻刷新展示。
  static Future<void> setPanelStyle(PanelStyleMode style) async {
    await HiveService.setSetting<int>(kPrefPanelStyle, style.persistValue);
    if (isOngoingPanelEnabled) {
      await refreshOngoingPanel();
    }
  }

  /// 设置响铃模式：持久化 + 立刻重排所有待办（让 pending 通知走新渠道）。
  static Future<void> setReminderAlertMode(ReminderAlertMode mode) async {
    await HiveService.setSetting<int>(
      kPrefReminderAlertMode,
      mode.persistValue,
    );
    await rescheduleAllFromHive();
  }

  /// 设置开机自启：持久化 + 同步原生 SharedPreferences。
  /// 实际效果在下一次设备重启后由 BootReceiver 生效。
  static Future<void> setBootStartEnabled(bool enabled) async {
    await HiveService.setSetting<bool>(kPrefBootStartEnabled, enabled);
    await NativePrefs.setBool(NativePrefs.kBootStartEnabled, enabled);
  }

  /// 根据当前 Hive 中的待办实时生成面板文案并刷新。
  static Future<void> refreshOngoingPanel() async {
    if (!Platform.isAndroid || !_initialized) return;

    final todos = HiveService.getAllTodos();
    var total = todos.length;
    var done = 0;
    var overdue = 0;
    final pendingList = <TodoModel>[];
    final nowTs = DateTime.now();
    bool isOverdue(TodoModel t) {
      final r = t.remindAt;
      return r != null && r.isBefore(nowTs);
    }

    for (final t in todos) {
      if (t.done) {
        done++;
      } else {
        pendingList.add(t);
        if (isOverdue(t)) overdue++;
      }
    }
    final pending = pendingList.length;

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

    // 详细样式：BigText 多行列出前 5 条未完成待办（逾期优先、然后按提醒时间升序）
    StyleInformation? style;
    if (panelStyle == PanelStyleMode.detailed && pendingList.isNotEmpty) {
      pendingList.sort((a, b) {
        final ao = isOverdue(a) ? 0 : 1;
        final bo = isOverdue(b) ? 0 : 1;
        if (ao != bo) return ao - bo;
        final ad = a.remindAt?.millisecondsSinceEpoch ?? 1 << 62;
        final bd = b.remindAt?.millisecondsSinceEpoch ?? 1 << 62;
        return ad.compareTo(bd);
      });
      final top = pendingList.take(5).map((t) {
        final prefix = isOverdue(t) ? '⚠ ' : '• ';
        return '$prefix${t.title.isEmpty ? '(未命名)' : t.title}';
      }).join('\n');
      final more = pendingList.length > 5
          ? '\n…还有 ${pendingList.length - 5} 条'
          : '';
      style = BigTextStyleInformation(
        '$top$more',
        contentTitle: title,
        summaryText: body,
      );
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
      styleInformation: style,
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
