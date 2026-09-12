import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:omninest/platform/desktop/desktop_single_instance.dart';
import 'package:omninest/platform/desktop/desktop_tray_service.dart';
import 'package:omninest/platform/desktop/desktop_hotkey_service.dart';
import 'package:omninest/platform/platform_capabilities.dart';
import 'package:window_manager/window_manager.dart';

/// 桌面壳层引导：单实例锁 + 系统托盘 + 关窗隐藏（退出仅走托盘菜单）。
///
/// 由条件导入门面在 IO 平台调用，移动端与 Web 为空实现。
Future<void> bootstrapDesktopShell() async {
  if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
    return;
  }
  await ensureSingleDesktopInstance();
  // B5：托盘初始化由平台能力驱动，而非散落的平台判断。
  if (!PlatformCapabilities.current().supportsSystemTray) {
    return;
  }
  await windowManager.ensureInitialized();
  await windowManager.setPreventClose(true);
  await DesktopTrayService().init();
  // E1：系统级媒体键（播放/暂停、上一首、下一首），命令由音乐播放会话层桥接。
  await DesktopHotkeyService().registerMediaKeys();
  debugPrint('桌面壳层初始化完成：托盘与关窗隐藏已启用');
}
