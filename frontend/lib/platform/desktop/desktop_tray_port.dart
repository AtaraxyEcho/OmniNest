// tray_manager 0.7 将 0.5.x API 整体标为弃用并迁到 legacy 桥接层；
// 本文件是应用侧稳定端口，避免业务代码直接依赖将被删除的上游符号。
// ignore_for_file: deprecated_member_use

import 'package:tray_manager/legacy.dart';

export 'package:tray_manager/legacy.dart'
    show Menu, MenuItem, TrayIconPosition, TrayListener;

/// 托盘原生操作端口。
///
/// `tray_manager` 0.7 的实现走 nativeapi FFI，单元测试无法再打
/// `MethodChannel('tray_manager')`。业务侧只依赖本接口，测试注入假实现。
abstract class DesktopTrayPort {
  void addListener(TrayListener listener);

  void removeListener(TrayListener listener);

  Future<void> setIcon(String iconPath, {bool isTemplate = false});

  Future<void> setToolTip(String text);

  Future<void> setContextMenu(Menu menu);

  Future<void> popUpContextMenu({bool bringAppToFront = false});

  Future<void> destroy();
}

/// 默认端口：转发到 `tray_manager` legacy 单例。
class LegacyDesktopTrayPort implements DesktopTrayPort {
  const LegacyDesktopTrayPort();

  @override
  void addListener(TrayListener listener) {
    trayManager.addListener(listener);
  }

  @override
  void removeListener(TrayListener listener) {
    trayManager.removeListener(listener);
  }

  @override
  Future<void> setIcon(String iconPath, {bool isTemplate = false}) {
    return trayManager.setIcon(iconPath, isTemplate: isTemplate);
  }

  @override
  Future<void> setToolTip(String text) {
    return trayManager.setToolTip(text);
  }

  @override
  Future<void> setContextMenu(Menu menu) {
    return trayManager.setContextMenu(menu);
  }

  @override
  Future<void> popUpContextMenu({bool bringAppToFront = false}) {
    return trayManager.popUpContextMenu(bringAppToFront: bringAppToFront);
  }

  @override
  Future<void> destroy() {
    return trayManager.destroy();
  }
}
