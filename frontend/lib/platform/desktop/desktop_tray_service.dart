import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:omninest/core/widgets/brand_logo.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// 桌面系统托盘服务。
/// 提供托盘图标、右键菜单、单击还原和关窗隐藏；退出仅经托盘菜单。
class DesktopTrayService with TrayListener, WindowListener {
  DesktopTrayService();

  bool _initialized = false;
  bool _quitting = false;

  /// 初始化系统托盘与窗口关闭拦截。
  Future<void> init() async {
    if (_initialized) return;
    trayManager.addListener(this);
    windowManager.addListener(this);

    await _setIconWithRetry();

    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show', label: '显示窗口'),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: '退出'),
        ],
      ),
    );

    _initialized = true;
  }

  /// 设置托盘图标；窗口/托盘宿主未就绪时会静默失败，短延迟重试一次。
  Future<void> _setIconWithRetry() async {
    try {
      await trayManager.setIcon(BrandLogo.assetPath, isTemplate: false);
    } on Object catch (error) {
      debugPrint('托盘图标首次设置失败，稍后重试: $error');
      await Future<void>.delayed(const Duration(milliseconds: 400));
      try {
        await trayManager.setIcon(BrandLogo.assetPath, isTemplate: false);
      } on Object catch (retryError) {
        debugPrint('托盘图标设置仍失败: $retryError');
      }
    }
  }

  /// 移除托盘图标并注销监听。
  Future<void> dispose() async {
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    await trayManager.destroy();
    _initialized = false;
  }

  /// 托盘菜单退出：先摘除关闭拦截与托盘，再销毁窗口，
  /// 避免 preventClose 的 onWindowClose(hide) 拖住销毁流程造成假死。
  Future<void> quit() async {
    if (_quitting) return;
    _quitting = true;
    windowManager.removeListener(this);
    try {
      await trayManager.destroy();
    } on Object catch (error) {
      debugPrint('托盘销毁失败（忽略继续退出）: $error');
    }
    await windowManager.destroy();
  }

  @override
  void onTrayIconMouseDown() {
    windowManager.show();
    windowManager.focus();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        windowManager.show();
        windowManager.focus();
      case 'quit':
        unawaited(quit());
      default:
        break;
    }
  }

  @override
  void onWindowClose() {
    // preventClose 已开启：关闭按钮隐藏到托盘，退出仅走托盘菜单。
    windowManager.hide();
  }
}
