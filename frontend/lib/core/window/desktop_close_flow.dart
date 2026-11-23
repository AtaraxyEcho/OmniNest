import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omninest/core/window/desktop_close_action.dart';
import 'package:omninest/core/window/desktop_close_confirm_dialog.dart';
import 'package:omninest/core/log/dev_log.dart';

/// 桌面端主窗口关闭流程：确认弹窗、记住偏好与托盘动作的统一入口。
///
/// 由桌面壳层在启动时注入动作回调，窗口关闭拦截统一委托本流程处理，
/// 避免 Web 与移动端引入桌面专属依赖。
class DesktopCloseFlow {
  static final DesktopCloseFlow instance = DesktopCloseFlow._();

  /// 设备级偏好在 SharedPreferences 中的键；缺失表示每次关闭时询问。
  static const String rememberedActionKey = 'desktop.close.rememberedAction';

  DesktopCloseFlow._();

  bool _handling = false;
  Future<void> Function()? _hideWindow;
  Future<void> Function()? _quitApp;
  bool Function()? _isTrayReady;

  /// 注入隐藏窗口、退出应用与托盘就绪判定回调，须在窗口可交互前完成。
  void bind({
    required Future<void> Function() hideWindow,
    required Future<void> Function() quitApp,
    bool Function()? isTrayReady,
  }) {
    _hideWindow = hideWindow;
    _quitApp = quitApp;
    _isTrayReady = isTrayReady;
  }

  bool get _trayReady => _isTrayReady?.call() ?? true;

  /// 读取记住的关闭动作；null 表示每次询问。
  Future<DesktopCloseAction?> readRememberedAction() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(rememberedActionKey);
    if (raw == DesktopCloseAction.minimizeToTray.name) {
      return DesktopCloseAction.minimizeToTray;
    }
    if (raw == DesktopCloseAction.exitApp.name) {
      return DesktopCloseAction.exitApp;
    }
    return null;
  }

  /// 记住关闭动作；传 null 清除偏好，恢复每次询问。
  Future<void> rememberAction(DesktopCloseAction? action) async {
    final preferences = await SharedPreferences.getInstance();
    if (action == null) {
      await preferences.remove(rememberedActionKey);
      return;
    }
    await preferences.setString(rememberedActionKey, action.name);
  }

  /// 处理一次主窗口关闭请求。
  ///
  /// 托盘尚未初始化、导航未就绪或确认流程异常时直接退出应用，绝不把窗口
  /// 隐藏进尚未存在的托盘造成“无窗无托盘”幽灵进程。
  Future<void> handleWindowCloseRequest() async {
    if (_handling) {
      return;
    }
    _handling = true;
    try {
      if (!_trayReady) {
        await _apply(DesktopCloseAction.exitApp);
        return;
      }
      final remembered = await readRememberedAction();
      if (remembered != null) {
        await _apply(remembered);
        return;
      }
      final navigatorContext = desktopCloseNavigatorKey.currentContext;
      if (navigatorContext == null || !navigatorContext.mounted) {
        await _apply(DesktopCloseAction.exitApp);
        return;
      }
      final decision = await showDesktopCloseConfirmDialog(navigatorContext);
      if (decision == null) {
        return;
      }
      if (decision.remember) {
        await rememberAction(decision.action);
      }
      await _apply(decision.action);
    } on Object catch (error) {
      devLog('关闭确认流程失败，回退为直接退出: $error');
      await _apply(DesktopCloseAction.exitApp);
    } finally {
      _handling = false;
    }
  }

  Future<void> _apply(DesktopCloseAction action) async {
    final effectiveAction =
        action == DesktopCloseAction.minimizeToTray && !_trayReady
            ? DesktopCloseAction.exitApp
            : action;
    switch (effectiveAction) {
      case DesktopCloseAction.minimizeToTray:
        final hide = _hideWindow;
        if (hide != null) {
          await hide();
        }
      case DesktopCloseAction.exitApp:
        final quit = _quitApp;
        if (quit != null) {
          await quit();
        }
    }
  }

  @visibleForTesting
  void reset() {
    _handling = false;
    _hideWindow = null;
    _quitApp = null;
    _isTrayReady = null;
  }
}
