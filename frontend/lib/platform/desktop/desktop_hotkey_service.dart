import 'dart:async';

import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:omninest/features/music/application/music_media_session.dart';

/// Desktop 全局快捷键服务。
/// 注册系统级快捷键用于快速显示/隐藏窗口。
class DesktopHotkeyService {
  DesktopHotkeyService();

  final List<HotKey> _registered = [];

  /// 注册全局快捷键。
  Future<void> registerGlobalHotkeys() async {
    // Cmd/Ctrl + Shift + O: 显示/隐藏窗口
    final toggleHotKey = HotKey(
      key: PhysicalKeyboardKey.keyO,
      modifiers: [HotKeyModifier.shift, HotKeyModifier.meta],
      scope: HotKeyScope.system,
    );

    await hotKeyManager.register(
      toggleHotKey,
      keyDownHandler: (_) async {
        if (await windowManager.isVisible()) {
          await windowManager.hide();
        } else {
          await windowManager.show();
          await windowManager.focus();
        }
      },
    );
    _registered.add(toggleHotKey);
  }

  /// 注册系统级媒体键（播放/暂停、上一首、下一首）。
  ///
  /// 回调经 MusicMediaKeyBridge 转接音乐播放会话层注入的命令。
  Future<void> registerMediaKeys() async {
    final playPauseKey = HotKey(
      key: PhysicalKeyboardKey.mediaPlay,
      scope: HotKeyScope.system,
    );
    await hotKeyManager.register(
      playPauseKey,
      keyDownHandler: (_) {
        unawaited(MusicMediaKeyBridge.dispatch(play: true, pause: true));
      },
    );
    _registered.add(playPauseKey);

    final nextKey = HotKey(
      key: PhysicalKeyboardKey.mediaTrackNext,
      scope: HotKeyScope.system,
    );
    await hotKeyManager.register(
      nextKey,
      keyDownHandler: (_) {
        unawaited(MusicMediaKeyBridge.dispatch(play: false, next: true));
      },
    );
    _registered.add(nextKey);

    final previousKey = HotKey(
      key: PhysicalKeyboardKey.mediaTrackPrevious,
      scope: HotKeyScope.system,
    );
    await hotKeyManager.register(
      previousKey,
      keyDownHandler: (_) {
        unawaited(MusicMediaKeyBridge.dispatch(play: false, previous: true));
      },
    );
    _registered.add(previousKey);
  }

  /// 注销所有快捷键。
  Future<void> dispose() async {
    for (final hotKey in _registered) {
      await hotKeyManager.unregister(hotKey);
    }
    _registered.clear();
  }
}
