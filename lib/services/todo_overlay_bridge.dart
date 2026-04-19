import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import '../widgets/todo_editor_sheet.dart';
import '../widgets/todo_quick_actions.dart';
import 'hive_service.dart';
import 'native_prefs.dart';

/// Hive 设置：为 true 且已授予悬浮窗权限时，从通知点待办优先用悬浮窗。
const String kPrefNotificationQuickOverlay =
    'notification_quick_overlay_enabled';

/// 悬浮窗成功弹出后是否将主 Activity 退到后台（减轻「先进全屏应用」观感）。
const String kPrefMoveTaskBackAfterTodoOverlay =
    'move_task_back_after_todo_overlay';

/// Android 通知快捷操作悬浮窗：主引擎侧逻辑与 [overlayMain] 配对。
class TodoOverlayBridge {
  TodoOverlayBridge._();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static bool _mainListenerAttached = false;
  static StreamSubscription<dynamic>? _overlaySub;

  /// 最近一次 [tryShow] 已走完 Dart 侧流程的待办 id；[TodoPage] 用 [consumeOverlaySkipTodoQuickUiIfShowing] 结合 [isActive] 决定是否跳过弹窗。
  static String? _overlayShownPayloadId;

  /// 若本 id 已被 [tryShow] 认领且悬浮窗当前仍在显示，返回 true（并清除认领，主界面可跳过弹窗）。
  ///
  /// 若认领了但悬浮窗未附着（竞态、权限或服务失败），返回 false，便于回退到居中快捷弹窗。
  static Future<bool> consumeOverlaySkipTodoQuickUiIfShowing(String id) async {
    if (_overlayShownPayloadId != id) return false;
    if (!Platform.isAndroid) {
      _overlayShownPayloadId = null;
      return false;
    }
    try {
      final active = await FlutterOverlayWindow.isActive();
      _overlayShownPayloadId = null;
      return active;
    } catch (_) {
      _overlayShownPayloadId = null;
      return false;
    }
  }

  /// 在根 [MaterialApp] 挂载后调用一次（例如 [MyApp] `initState`）。
  static void initMainSide() {
    if (_mainListenerAttached) return;
    _mainListenerAttached = true;
    _overlaySub = FlutterOverlayWindow.overlayListener.listen(_onOverlayEvent);
  }

  /// 可选：应用退出时调用（当前未在 dispose 中调用以避免影响插件单例）。
  static void disposeMainSide() {
    _overlaySub?.cancel();
    _overlaySub = null;
    _mainListenerAttached = false;
  }

  static Map<String, dynamic>? _normalizeEventMap(dynamic event) {
    if (event is Map<String, dynamic>) return event;
    if (event is Map) {
      return event.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  static void _onOverlayEvent(dynamic event) {
    final map = _normalizeEventMap(event);
    if (map == null) return;
    final cmd = map['cmd']?.toString();
    final id = map['id']?.toString();
    if (id == null || id.isEmpty) return;

    switch (cmd) {
      case 'toggle_done':
        unawaited(HiveService.toggleDone(id));
        return;
      case 'open_editor':
        final todo = HiveService.getTodoById(id);
        if (todo == null) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = navigatorKey.currentContext;
          if (ctx != null && ctx.mounted) {
            showTodoEditor(ctx, todo: todo);
          }
        });
        return;
      default:
        return;
    }
  }

  /// 尝试显示通知快捷悬浮窗。失败时由调用方回退 [showTodoQuickActions]。
  static Future<bool> tryShowQuickActionsForTodoId(String id) async {
    if (!Platform.isAndroid) return false;
    if (!HiveService.getSetting<bool>(kPrefNotificationQuickOverlay, false)) {
      return false;
    }
    if (!await FlutterOverlayWindow.isPermissionGranted()) return false;

    final todo = HiveService.getTodoById(id);
    if (todo == null) return false;

    try {
      if (await FlutterOverlayWindow.isActive()) {
        await FlutterOverlayWindow.closeOverlay();
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }

      final view = PlatformDispatcher.instance.views.first;
      final logicalH = view.physicalSize.height / view.devicePixelRatio;
      final overlayHeight = (logicalH * 0.52).round().clamp(280, 720);

      await FlutterOverlayWindow.showOverlay(
        height: overlayHeight,
        width: WindowSize.matchParent,
        alignment: OverlayAlignment.center,
        flag: OverlayFlag.defaultFlag,
        enableDrag: true,
        positionGravity: PositionGravity.auto,
        overlayTitle: '待办快捷操作',
        overlayContent: todo.title.isEmpty ? '待办' : todo.title,
      );

      // 给 OverlayService 附着 FlutterView 一帧时间；数据在 overlay_main 里已尽早注册通道。
      await Future<void>.delayed(const Duration(milliseconds: 32));
      final snapshot = TodoQuickActionViewData.fromModel(todo).toShareMap();
      var dataDelivered = false;
      for (var attempt = 0; attempt < 40; attempt++) {
        try {
          await FlutterOverlayWindow.shareData(snapshot).timeout(
            const Duration(milliseconds: 450),
            onTimeout: () => throw TimeoutException('overlay shareData'),
          );
          dataDelivered = true;
          break;
        } catch (_) {
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
      }
      if (!dataDelivered) {
        throw TimeoutException('overlay shareData after retries');
      }
    } catch (_) {
      try {
        await FlutterOverlayWindow.closeOverlay();
      } catch (_) {}
      return false;
    }
    _overlayShownPayloadId = id;
    if (HiveService.getSetting<bool>(kPrefMoveTaskBackAfterTodoOverlay, true)) {
      await Future<void>.delayed(const Duration(milliseconds: 450));
      await NativePrefs.moveTaskToBackIfAndroid();
    }
    return true;
  }
}
