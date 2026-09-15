import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:omninest/core/widgets/brand_logo.dart';
import 'package:omninest/core/window/desktop_close_flow.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// 桌面系统托盘服务。
///
/// 图标资源按平台选择：Windows 托盘走 `LoadImage(IMAGE_ICON)`，必须是
/// `.ico`（传 PNG 会静默拿到空图标）；macOS/Linux 使用 PNG。Windows/Linux
/// 会把相对路径拼到 `dirname(executable)/data/flutter_assets/` 下加载，
/// 因此使用已打包的 flutter asset 相对路径。
///
/// 窗口关闭拦截统一交给 [DesktopCloseFlow]（确认弹窗或记住的偏好），
/// 退出可来自托盘菜单或关闭确认窗，共用同一清理链路。窗口销毁链路在
/// Flutter 桌面引擎关停时可能长时间不返回，最终以短超时 + `exit(0)`
/// 兜底，避免托盘退出后假死数秒。
class DesktopTrayService with TrayListener, WindowListener {
  DesktopTrayService();

  /// Windows 托盘 ICO（多尺寸，由 flutter_assets 打包）。
  static const String windowsTrayIconAsset = 'assets/icon/tray.ico';

  /// 非 Windows 托盘 PNG。
  static const String posixTrayIconAsset = BrandLogo.assetPath;

  /// 托盘退出清理的硬超时；超时后强制结束进程。
  static const Duration quitCleanupBudget = Duration(milliseconds: 400);

  bool _initialized = false;
  bool _quitting = false;

  /// 初始化系统托盘与窗口关闭拦截。
  Future<void> init() async {
    if (_initialized) {
      return;
    }
    trayManager.addListener(this);
    windowManager.addListener(this);

    await _setIcon();
    try {
      await trayManager.setToolTip('OmniNest');
    } on Object catch (error) {
      debugPrint('托盘提示文案设置失败: $error');
    }

    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'brand', label: 'OmniNest', disabled: true),
          MenuItem.separator(),
          MenuItem(key: 'show', label: '显示主窗口'),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: '退出'),
        ],
      ),
    );

    _initialized = true;
  }

  Future<void> _setIcon() async {
    final iconPath =
        defaultTargetPlatform == TargetPlatform.windows
            ? windowsTrayIconAsset
            : posixTrayIconAsset;
    try {
      await trayManager.setIcon(iconPath, isTemplate: false);
    } on Object catch (error) {
      debugPrint('托盘图标设置失败: $error');
    }
  }

  /// 移除托盘图标并注销监听。
  Future<void> dispose() async {
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    if (_initialized) {
      await trayManager.destroy();
    }
    _initialized = false;
  }

  /// 托盘菜单退出：短清理后立即结束进程。
  ///
  /// `windowManager.destroy()` 在 Windows 仅 `PostQuitMessage`，但 Flutter
  /// 引擎关停、media 等插件释放仍可能挂住平台通道；清理预算结束后强制
  /// `exit(0)`，避免托盘“退出”后窗口假死数秒。
  Future<void> quit() async {
    if (_quitting) {
      return;
    }
    _quitting = true;
    debugPrint('托盘退出流程开始');
    windowManager.removeListener(this);
    await Future.any([
      _cleanupBeforeExit(),
      Future<void>.delayed(quitCleanupBudget),
    ]);
    debugPrint('托盘退出：结束进程');
    exit(0);
  }

  Future<void> _cleanupBeforeExit() async {
    try {
      await trayManager.destroy();
    } on Object catch (error) {
      debugPrint('托盘销毁失败（忽略继续退出）: $error');
    }
    try {
      await windowManager.setPreventClose(false);
    } on Object catch (error) {
      debugPrint('解除关闭拦截失败: $error');
    }
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(_showAndFocus());
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(
      trayManager.popUpContextMenu().catchError((Object error) {
        debugPrint('托盘右键菜单弹出失败: $error');
      }),
    );
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        unawaited(_showAndFocus());
      case 'quit':
        unawaited(quit());
      default:
        break;
    }
  }

  @override
  void onWindowClose() {
    // preventClose 已开启：关闭动作交由关闭确认流程决定（弹窗询问或执行记住的偏好）。
    unawaited(DesktopCloseFlow.instance.handleWindowCloseRequest());
  }

  Future<void> _showAndFocus() async {
    await windowManager.show();
    await windowManager.focus();
  }
}
