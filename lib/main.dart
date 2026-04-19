import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'main_page.dart';
import 'overlay_main.dart' show overlayMain;
import 'services/display_refresh_service.dart';
import 'services/hive_service.dart';
import 'services/notification_service.dart';
import 'services/todo_overlay_bridge.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await preferHighRefreshRateIfSupported();

  await HiveService.init();
  await NotificationService.init();
  // 兜底：升级/重装/时区变更后把 Hive 中仍需提醒的待办重新排期
  await NotificationService.rescheduleAllFromHive();
  // 常驻面板：状态栏显示待办进度 + 快捷添加
  await NotificationService.startOngoingPanel();

  // 避免 release 摇树移除 [overlayMain]。
  final void Function() overlayEntryKeep = overlayMain;
  assert(overlayEntryKeep == overlayMain);

  // 悬浮窗监听须在 [tryShow] 之前注册；并尽早尝试冷启动「点通知进待办」悬浮窗，避免等 [TodoPage] 首帧。
  TodoOverlayBridge.initMainSide();
  NotificationService.androidTodoTapPreprocessor = (id) async {
    await TodoOverlayBridge.tryShowQuickActionsForTodoId(id);
  };

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    TodoOverlayBridge.initMainSide();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(preferHighRefreshRateIfSupported());
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: TodoOverlayBridge.navigatorKey,
      title: '日历应用',
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MainPage(),
    );
  }
}
