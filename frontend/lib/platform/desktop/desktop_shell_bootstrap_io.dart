import 'dart:async';

import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:omninest/core/window/desktop_close_flow.dart';
import 'package:omninest/platform/desktop/desktop_single_instance.dart';
import 'package:omninest/platform/desktop/desktop_tray_service.dart';
import 'package:omninest/platform/desktop/desktop_hotkey_service.dart';
import 'package:omninest/platform/platform_capabilities.dart';
import 'package:window_manager/window_manager.dart';
import 'package:omninest/core/log/dev_log.dart';

/// 桌面壳层引导：单实例锁 + 系统托盘 + 关闭确认流程（退出或最小化到托盘）。
///
/// 由条件导入门面在 IO 平台调用，移动端与 Web 为空实现。
Future<void> bootstrapDesktopShell() async {
  if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
    return;
  }
  await ensureSingleDesktopInstance(arguments: Platform.executableArguments);
  // B5：托盘初始化由平台能力驱动，而非散落的平台判断。
  if (!PlatformCapabilities.current().supportsSystemTray) {
    return;
  }
  await windowManager.ensureInitialized();
  await windowManager.setPreventClose(true);
  final trayService = DesktopTrayService();
  DesktopCloseFlow.instance.bind(
    hideWindow: windowManager.hide,
    quitApp: trayService.quit,
  );
  await trayService.init();
  // E1：系统级媒体键（播放/暂停、上一首、下一首），命令由音乐播放会话层桥接。
  await DesktopHotkeyService().registerMediaKeys();
  unawaited(_registerDeepLinkProtocol());
  devLog('桌面壳层初始化完成：托盘与关闭确认流程已启用');
}

/// 注册 `omninest://` 深链协议到当前用户（无需管理员）。
///
/// Windows 写 HKCU 注册表；macOS 由 `Info.plist` CFBundleURLTypes 声明；
/// Linux 写用户级 `.desktop` 并设置 xdg-mime 默认处理器。注册失败不影响主体。
/// 能力由 [PlatformCapabilities.supportsDeepLinkProtocol] 门控。
Future<void> _registerDeepLinkProtocol() async {
  if (!PlatformCapabilities.current().supportsDeepLinkProtocol) {
    return;
  }
  try {
    if (Platform.isWindows) {
      await _registerWindowsProtocol();
      return;
    }
    if (Platform.isLinux) {
      await _registerLinuxProtocol();
    }
  } on Exception {
    // 协议注册失败不影响应用主体功能。
  }
}

/// Windows 注册 omninest:// 协议到当前用户注册表（无需管理员）。
Future<void> _registerWindowsProtocol() async {
  final exe = Platform.resolvedExecutable;
  final command = '"$exe" "%1"';
  await Process.run('reg', [
    'add',
    r'HKCU\Software\Classes\omninest',
    '/ve',
    '/d',
    'URL:OmniNest Protocol',
    '/f',
  ]);
  await Process.run('reg', [
    'add',
    r'HKCU\Software\Classes\omninest',
    '/v',
    'URL Protocol',
    '/d',
    '',
    '/f',
  ]);
  await Process.run('reg', [
    'add',
    r'HKCU\Software\Classes\omninest\shell\open\command',
    '/ve',
    '/d',
    command,
    '/f',
  ]);
}

/// Linux 写用户级 desktop 文件并注册 x-scheme-handler/omninest。
Future<void> _registerLinuxProtocol() async {
  final home = Platform.environment['HOME'];
  if (home == null || home.isEmpty) {
    return;
  }
  final appDir = Directory('$home/.local/share/applications');
  if (!appDir.existsSync()) {
    appDir.createSync(recursive: true);
  }
  final desktopFile = File('${appDir.path}/omninest.desktop');
  desktopFile.writeAsStringSync(
    buildLinuxDesktopEntry(Platform.resolvedExecutable),
  );
  await Process.run('xdg-mime', [
    'default',
    'omninest.desktop',
    'x-scheme-handler/omninest',
  ]);
  await Process.run('update-desktop-database', [appDir.path]);
}

/// 生成 Linux 用户级 `omninest.desktop` 文本，供深链协议注册与测试共用。
@visibleForTesting
String buildLinuxDesktopEntry(String executablePath) {
  return '''
[Desktop Entry]
Name=OmniNest
Comment=OmniNest self-hosted media center
Exec="$executablePath" "%u"
Icon=omninest
Terminal=false
Type=Application
MimeType=x-scheme-handler/omninest;
''';
}
