import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omninest/core/window/desktop_close_action.dart';
import 'package:omninest/core/window/desktop_close_confirm_dialog.dart';

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

  /// 注入隐藏窗口与退出应用的回调，须在窗口可交互前完成。
  void bind({
    required Future<void> Function() hideWindow,
    required Future<void> Function() quitApp,
  }) {
    _hideWindow = hideWindow;
    _quitApp = quitApp;
  }

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
  /// 已记住偏好时直接执行对应动作；否则弹出确认窗。导航未就绪或流程
  /// 异常时回退为隐藏到托盘，保持升级前的行为兜底，避免窗口无法关闭。
  Future<void> handleWindowCloseRequest() async {
    if (_handling) {
      return;
    }
    _handling = true;
    try {
      final remembered = await readRememberedAction();
      if (remembered != null) {
        await _apply(remembered);
        return;
      }
      final navigatorContext = desktopCloseNavigatorKey.currentContext;
      if (navigatorContext == null || !navigatorContext.mounted) {
        await _apply(DesktopCloseAction.minimizeToTray);
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
      debugPrint('关闭确认流程失败，回退为隐藏到托盘: $error');
      await _apply(DesktopCloseAction.minimizeToTray);
    } finally {
      _handling = false;
    }
  }

  Future<void> _apply(DesktopCloseAction action) async {
    switch (action) {
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
  }
}
