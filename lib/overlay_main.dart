import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import 'widgets/todo_quick_actions.dart';

/// 悬浮窗 Flutter 引擎入口（插件写死调用名 [overlayMain]）。
@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  // 访问 getter 会注册 BasicMessageChannel 处理端；否则首帧前主引擎 shareData 可能长时间无人应答。
  final _ = FlutterOverlayWindow.overlayListener;
  runApp(const _OverlayRootApp());
}

class _OverlayRootApp extends StatelessWidget {
  const _OverlayRootApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const _OverlayHome(),
    );
  }
}

class _OverlayHome extends StatefulWidget {
  const _OverlayHome();

  @override
  State<_OverlayHome> createState() => _OverlayHomeState();
}

class _OverlayHomeState extends State<_OverlayHome> {
  TodoQuickActionViewData? _data;
  StreamSubscription<dynamic>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = FlutterOverlayWindow.overlayListener.listen(_onMessage);
  }

  void _onMessage(dynamic event) {
    final map = _asObjectKeyMap(event);
    if (map == null) return;
    if (map['cmd']?.toString() != 'snapshot') return;
    final next = TodoQuickActionViewData.fromMap(map);
    if (!mounted) return;
    setState(() => _data = next);
  }

  static Map<Object?, Object?>? _asObjectKeyMap(dynamic event) {
    if (event is Map<Object?, Object?>) return event;
    if (event is Map) {
      return event.map((k, v) => MapEntry(k, v));
    }
    return null;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _sendCmd(String cmd) async {
    final id = _data?.id;
    if (id == null || id.isEmpty) return;
    await FlutterOverlayWindow.shareData({'cmd': cmd, 'id': id});
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await FlutterOverlayWindow.closeOverlay();
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    if (d == null) {
      final scheme = Theme.of(context).colorScheme;
      return Material(
        color: Colors.transparent,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: Colors.black.withValues(alpha: 0.38)),
            Center(
              child: Material(
                elevation: 10,
                borderRadius: BorderRadius.circular(20),
                color: scheme.surface,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 36, vertical: 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: scheme.primary,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        '正在载入待办…',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '首次打开可能稍慢',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: Center(
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          elevation: 8,
          borderRadius: BorderRadius.circular(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: TodoQuickActionsBody(
                data: d,
                onDone: () => unawaited(_sendCmd('toggle_done')),
                onEdit: () => unawaited(_sendCmd('open_editor')),
                onCancel: () => unawaited(FlutterOverlayWindow.closeOverlay()),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
