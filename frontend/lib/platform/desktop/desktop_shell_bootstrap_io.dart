import 'dart:async';

import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:omninest/core/window/desktop_close_flow.dart';
import 'package:omninest/platform/desktop/desktop_single_instance.dart';
import 'package:omninest/platform/desktop/desktop_tray_service.dart';
import 'package:omninest/platform/desktop/desktop_hotkey_service.dart';
import 'package:omninest/platform/platform_capabilities.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:omninest/core/log/dev_log.dart';

/// 缓存已注册 `omninest://` 协议的 Windows 可执行文件绝对路径，
/// 路径未变时跳过重复 fork `reg.exe`。
const String _windowsProtocolExePrefsKey = 'desktop.deeplink.windows_exe.v1';

/// 首帧后延迟初始化非关键桌面外围能力（托盘、全局媒体键、深链协议注册）。
const Duration _deferredShellInitDelay = Duration(milliseconds: 500);

Timer? _deferredShellInitTimer;
bool _deferredShellInitCancelled = false;

/// 串行保证桌面端 `windowManager.ensureInitialized()` 完成，避免并发初始化竞态。
Future<void> ensureDesktopWindowManagerInitialized() async {
  if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
    return;
  }
  await windowManager.ensureInitialized();
}

/// 取消尚未触发的延迟壳层初始化计时器（如用户在首帧 500ms 内触发退出）。
void cancelDeferredDesktopShellInit() {
  _deferredShellInitCancelled = true;
  _deferredShellInitTimer?.cancel();
  _deferredShellInitTimer = null;
}

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
  await ensureDesktopWindowManagerInitialized();
  final trayService = DesktopTrayService();
  DesktopCloseFlow.instance.bind(
    hideWindow: windowManager.hide,
    quitApp: () {
      cancelDeferredDesktopShellInit();
      return trayService.quit();
    },
    isTrayReady: () => trayService.isInitialized,
  );
  // 先挂载 WindowListener 再开启 preventClose，消除首帧 500ms 内早关窗空窗。
  trayService.attachWindowListener();
  await windowManager.setPreventClose(true);
  _deferredShellInitTimer?.cancel();
  _deferredShellInitTimer = null;
  _deferredShellInitCancelled = false;
  // 托盘、媒体键与深链协议注册移出冷启动关键路径，首帧渲染完成 500ms 后再执行。
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_deferredShellInitCancelled) {
      return;
    }
    _deferredShellInitTimer?.cancel();
    _deferredShellInitTimer = Timer(_deferredShellInitDelay, () {
      _deferredShellInitTimer = null;
      if (_deferredShellInitCancelled) {
        return;
      }
      unawaited(_initDeferredDesktopShell(trayService));
    });
  });
}

Future<void> _initDeferredDesktopShell(DesktopTrayService trayService) async {
  try {
    await trayService.init();
  } on Object catch (error) {
    devLog('桌面托盘初始化失败: $error');
  }
  try {
    // E1：系统级媒体键（播放/暂停、上一首、下一首），命令由音乐播放会话层桥接。
    await DesktopHotkeyService.instance.registerMediaKeys();
  } on Object catch (error) {
    devLog('桌面媒体键注册失败: $error');
  }
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
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_windowsProtocolExePrefsKey) == exe) {
      return;
    }
  } on Object {
    // 读取缓存失败时回退执行注册。
  }
  // -- 终止选项解析：主题或深链参数以 -- 开头时不会被引擎当成启动开关。
  final command = '"$exe" -- "%1"';
  final results = await Future.wait<ProcessResult>([
    Process.run('reg', [
      'add',
      r'HKCU\Software\Classes\omninest',
      '/ve',
      '/d',
      'URL:OmniNest Protocol',
      '/f',
    ]),
    Process.run('reg', [
      'add',
      r'HKCU\Software\Classes\omninest',
      '/v',
      'URL Protocol',
      '/d',
      '',
      '/f',
    ]),
    Process.run('reg', [
      'add',
      r'HKCU\Software\Classes\omninest\shell\open\command',
      '/ve',
      '/d',
      command,
      '/f',
    ]),
  ]);
  if (results.every((result) => result.exitCode == 0)) {
    try {
      await (prefs ?? await SharedPreferences.getInstance()).setString(
        _windowsProtocolExePrefsKey,
        exe,
      );
    } on Object {
      // 缓存写入失败不影响协议注册结果。
    }
  }
}

/// Linux 写用户级 desktop 文件并注册 x-scheme-handler/omninest。
Future<void> _registerLinuxProtocol() async {
  final home = Platform.environment['HOME'];
  if (home == null || home.isEmpty) {
    return;
  }
  final appDir = Directory('$home/.local/share/applications');
  if (!await appDir.exists()) {
    await appDir.create(recursive: true);
  }
  final desktopFile = File('${appDir.path}/omninest.desktop');
  await desktopFile.writeAsString(
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
