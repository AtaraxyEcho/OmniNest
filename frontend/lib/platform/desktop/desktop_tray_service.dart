import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
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

  /// 将图标资源解出为临时文件后以绝对路径设置。
  ///
  /// Windows 下 setIcon 对相对 asset 路径的解析依赖 flutter_assets 布局，
  /// release 包中存在静默失败案例；绝对文件路径在三个桌面平台行为一致。
  Future<void> _setIconWithRetry() async {
    final absolutePath = await _extractIconToTempFile();
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        if (absolutePath != null) {
          await trayManager.setIcon(absolutePath, isTemplate: false);
        } else {
          await trayManager.setIcon(BrandLogo.assetPath, isTemplate: false);
        }
        return;
      } on Object catch (error) {
        debugPrint('托盘图标设置失败（第 $attempt 次）: $error');
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }
  }

  Future<String?> _extractIconToTempFile() async {
    try {
      final data = await rootBundle.load(BrandLogo.assetPath);
      final file = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}omninest_tray_icon.png',
      );
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      return file.path;
    } on Object catch (error) {
      debugPrint('托盘图标资源解出失败: $error');
      return null;
    }
  }

  /// 移除托盘图标并注销监听。
  Future<void> dispose() async {
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    await trayManager.destroy();
    _initialized = false;
  }

  /// 托盘菜单退出：先摘除关闭拦截、解除 preventClose，再销毁托盘与窗口；
  /// 销毁超 3 秒未完成时强制结束进程，避免消息循环被拦出假死。
  Future<void> quit() async {
    if (_quitting) return;
    _quitting = true;
    debugPrint('托盘退出流程开始');
    windowManager.removeListener(this);
    try {
      await trayManager.destroy();
    } on Object catch (error) {
      debugPrint('托盘销毁失败（忽略继续退出）: $error');
    }
    try {
      // preventClose 的拦截发生在原生层，必须显式解除后销毁。
      await windowManager.setPreventClose(false);
    } on Object catch (error) {
      debugPrint('解除关闭拦截失败: $error');
    }
    try {
      await windowManager.destroy().timeout(const Duration(seconds: 3));
      debugPrint('窗口销毁完成');
    } on Object {
      debugPrint('窗口销毁超时，强制结束进程');
      exit(0);
    }
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
