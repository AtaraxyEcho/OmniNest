import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// 回到模块根路径时节流触发进入刷新的监听组件。
///
/// 主壳六分支常驻挂载于 IndexedStack，各中心 provider 为常驻缓存，重进
/// 分支本身不会发起新查询。本组件监听顶层路由 URI，路径回到
/// [modulePath] 且距上次刷新超过 [throttle] 时调用 [onRefresh]，实现
/// “再进入即取新”。首次挂载时仅注册监听不触发，初始加载由 provider
/// 自身 build 承担。
class ModuleEntryRefreshListener extends StatefulWidget {
  const ModuleEntryRefreshListener({
    required this.modulePath,
    required this.onRefresh,
    required this.child,
    this.throttle = const Duration(seconds: 15),
    super.key,
  });

  final String modulePath;

  final VoidCallback onRefresh;

  final Duration throttle;

  final Widget child;

  @override
  State<ModuleEntryRefreshListener> createState() =>
      _ModuleEntryRefreshListenerState();
}

class _ModuleEntryRefreshListenerState
    extends State<ModuleEntryRefreshListener> {
  GoRouter? _router;
  void Function()? _routeListener;
  DateTime _lastRefresh = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_router != null) {
      return;
    }
    _router = GoRouter.of(context);
    void listener() {
      if (!mounted) {
        return;
      }
      final path = _router!.routeInformationProvider.value.uri.path;
      if (path != widget.modulePath) {
        return;
      }
      final now = DateTime.now();
      if (now.difference(_lastRefresh) < widget.throttle) {
        return;
      }
      _lastRefresh = now;
      widget.onRefresh();
    }

    _routeListener = listener;
    _router!.routeInformationProvider.addListener(listener);
  }

  @override
  void dispose() {
    final router = _router;
    final listener = _routeListener;
    if (router != null && listener != null) {
      router.routeInformationProvider.removeListener(listener);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
