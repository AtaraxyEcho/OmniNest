// 经 DesktopTrayPort 使用 tray_manager 0.7 的 legacy 桥接类型；
// 上游迁移完成前这些符号仅在端口层可见，业务调用面保持稳定。
// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter/widgets.dart' show Locale;
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/locale/application/locale_controller.dart';
import 'package:omninest/app/preferences/app_bootstrap_data.dart';
import 'package:omninest/core/widgets/brand_logo.dart';
import 'package:omninest/core/window/desktop_close_flow.dart';
import 'package:omninest/platform/desktop/desktop_tray_port.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:omninest/core/log/dev_log.dart';

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
///
/// 右键菜单文案进入 ARB：初始化时按持久化的设备语言解析，运行期语言
/// 变化由应用层绑定经 [applyLanguage] 刷新。
///
/// 托盘原生操作经 [DesktopTrayPort] 注入：默认走 `tray_manager` 0.7 的
/// legacy 桥接层，测试可注入假实现而不触碰 FFI。
class DesktopTrayService with TrayListener, WindowListener {
  DesktopTrayService({DesktopTrayPort? tray})
    : _tray = tray ?? const LegacyDesktopTrayPort();

  /// 当前实例；应用层语言绑定经此刷新托盘文案，未初始化时为 null。
  static DesktopTrayService? get instance => _instance;

  static DesktopTrayService? _instance;

  /// Windows 托盘 ICO（多尺寸，由 flutter_assets 打包）。
  static const String windowsTrayIconAsset = 'assets/icon/tray.ico';

  /// 非 Windows 托盘 PNG。
  static const String posixTrayIconAsset = BrandLogo.assetPath;

  /// 托盘退出清理的硬超时；超时后强制结束进程。
  static const Duration quitCleanupBudget = Duration(milliseconds: 400);

  /// Windows 原生窗口帧通道，与 runner 的 flutter_window.cpp 对齐；
  /// window_chrome_controller 内亦声明了同名通道。
  static const MethodChannel _windowFrameChannel = MethodChannel(
    'omninest/window_frame',
  );

  final DesktopTrayPort _tray;
  bool _initialized = false;
  bool _quitting = false;

  /// 初始化系统托盘与窗口关闭拦截。
  Future<void> init() async {
    if (_initialized) {
      return;
    }
    _tray.addListener(this);
    windowManager.addListener(this);

    await _setIcon();
    try {
      await _tray.setToolTip('OmniNest');
    } on Object catch (error) {
      devLog('托盘提示文案设置失败: $error');
    }

    await _applyContextMenu();
    _initialized = true;
    _instance = this;
  }

  /// 按应用语言刷新托盘右键菜单文案；初始化完成前忽略。
  Future<void> applyLanguage(String languageCode) async {
    if (!_initialized) {
      return;
    }
    await _applyContextMenu(languageCode);
  }

  Future<void> _setIcon() async {
    final iconPath =
        defaultTargetPlatform == TargetPlatform.windows
            ? windowsTrayIconAsset
            : posixTrayIconAsset;
    try {
      await _tray.setIcon(iconPath, isTemplate: false);
    } on Object catch (error) {
      devLog('托盘图标设置失败: $error');
    }
  }

  /// 移除托盘图标并注销监听。
  Future<void> dispose() async {
    _tray.removeListener(this);
    windowManager.removeListener(this);
    if (_initialized) {
      await _tray.destroy();
    }
    _initialized = false;
    _instance = null;
  }

  /// 组装并应用右键菜单；菜单项 key 是托盘点击分发与测试的稳定契约。
  Future<void> _applyContextMenu([String? languageCode]) async {
    final resolved = languageCode ?? await _resolveLanguageCode();
    final l10n = lookupAppLocalizations(Locale(resolved));
    try {
      await _tray.setContextMenu(buildTrayMenu(l10n));
    } on Object catch (error) {
      devLog('托盘菜单设置失败: $error');
    }
  }

  /// 组装右键菜单：品牌禁用项 + 显示主窗口 + 退出。
  ///
  /// 抽为纯函数便于测试断言三段结构与 ARB 文案，不触碰托盘原生层。
  @visibleForTesting
  static Menu buildTrayMenu(AppLocalizations l10n) {
    return Menu(
      items: [
        MenuItem(key: 'brand', label: 'OmniNest', disabled: true),
        MenuItem.separator(),
        MenuItem(key: 'show', label: l10n.trayShowMainWindow),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: l10n.trayQuit),
      ],
    );
  }

  /// 解析托盘文案语言：设备偏好优先，缺失时跟随系统。
  ///
  /// 与应用启动期的语言解析保持同一键序（设备键 → 旧版全局键 → 系统语言）。
  Future<String> _resolveLanguageCode() async {
    final preferences = await SharedPreferences.getInstance();
    final stored =
        preferences.getString(localeDeviceLanguageKey) ??
        preferences.getString(legacyGlobalLanguageKey);
    return stored ?? resolveSystemLanguage();
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
    devLog('托盘退出流程开始');
    windowManager.removeListener(this);
    await Future.any([
      _cleanupBeforeExit(),
      Future<void>.delayed(quitCleanupBudget),
    ]);
    devLog('托盘退出：结束进程');
    exit(0);
  }

  Future<void> _cleanupBeforeExit() async {
    try {
      await _tray.destroy();
    } on Object catch (error) {
      devLog('托盘销毁失败（忽略继续退出）: $error');
    }
    try {
      await windowManager.setPreventClose(false);
    } on Object catch (error) {
      devLog('解除关闭拦截失败: $error');
    }
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(_showAndFocus());
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(popUpMenu());
  }

  /// 弹出托盘右键菜单。
  ///
  /// `bringAppToFront` 在 `tray_manager` 0.7 中已被上游忽略（仅保留参数
  /// 形状）；仍显式传 true，跟进上游若恢复该行为时无需再改调用点。
  /// 菜单关闭后补投 WM_NULL 收尾消息，避免下一次点击托盘时新菜单被旧
  /// 菜单状态立即吞掉。
  Future<void> popUpMenu() async {
    try {
      await _tray.popUpContextMenu(bringAppToFront: true);
    } on Object catch (error) {
      devLog('托盘右键菜单弹出失败: $error');
      return;
    }
    try {
      await _windowFrameChannel.invokeMethod<void>('finishTrayMenuPopup');
    } on Object catch (error) {
      devLog('托盘菜单收尾消息发送失败: $error');
    }
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
