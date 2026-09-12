import 'package:omninest/core/widgets/brand_logo.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// 桌面系统托盘服务。
/// 提供托盘图标、右键菜单、单击还原和关窗隐藏；退出仅经托盘菜单。
class DesktopTrayService with TrayListener, WindowListener {
  DesktopTrayService();

  bool _initialized = false;

  /// 初始化系统托盘与窗口关闭拦截。
  Future<void> init() async {
    if (_initialized) return;
    trayManager.addListener(this);
    windowManager.addListener(this);

    await trayManager.setIcon(BrandLogo.assetPath, isTemplate: false);

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

  /// 移除托盘图标并注销监听。
  Future<void> dispose() async {
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    await trayManager.destroy();
    _initialized = false;
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
        windowManager.destroy();
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
