import 'package:flutter/material.dart';

/// 桌面端关闭主窗口时执行的动作。
enum DesktopCloseAction {
  /// 隐藏窗口并保留托盘后台运行。
  minimizeToTray,

  /// 结束应用进程。
  exitApp,
}

/// 关闭确认弹窗的用户决策结果。
class DesktopCloseDecision {
  const DesktopCloseDecision({required this.action, required this.remember});

  /// 本次关闭执行的动作。
  final DesktopCloseAction action;

  /// 是否记住该选择，后续关闭不再询问。
  final bool remember;
}

/// 关闭确认弹窗依赖的根导航键，由 GoRouter 装配为主导航。
///
/// 桌面壳层在窗口关闭拦截中需要脱离具体页面上下文弹出弹窗，
/// 复用主导航可保证弹窗覆盖在所有路由与沉浸层之上。
final GlobalKey<NavigatorState> desktopCloseNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'desktop-close-root');
