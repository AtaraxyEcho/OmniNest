import 'dart:async';

import 'package:flutter/services.dart';
import 'package:omninest/features/music/application/music_media_session.dart';
import 'package:omninest/platform/platform_capabilities.dart';

/// Desktop 全局快捷键服务。
///
/// 当前仅桥接系统媒体键命令（播放/暂停、上一首、下一首）。
/// 系统级全局显隐热键不提供（未接线能力不得写入注释或能力位）。
class DesktopHotkeyService {
  DesktopHotkeyService();

  static const MethodChannel _hotkeyChannel = MethodChannel(
    'dev.leanflutter.plugins/hotkey_manager',
  );
  static const EventChannel _hotkeyEventChannel = EventChannel(
    'dev.leanflutter.plugins/hotkey_manager_event',
  );

  /// Windows 媒体键 VK 码：下一首、上一首、播放/暂停。
  static const int _vkMediaNextTrack = 0xB0;
  static const int _vkMediaPrevTrack = 0xB1;
  static const int _vkMediaPlayPause = 0xB3;

  final Map<String, void Function()> _mediaKeyDownHandlers =
      <String, void Function()>{};
  StreamSubscription<Object?>? _mediaKeyEventSub;

  /// 注册系统级媒体键（播放/暂停、上一首、下一首）。
  ///
  /// 媒体键不经过 hotkey_manager 公开 API：其 Dart 侧 keyCode 由 uni_platform
  /// 反查派生，Windows 上 mediaPlay、mediaTrackNext、mediaTrackPrevious 均
  /// 映射为 null，原生层反序列化 null keyCode 会 fail-fast 终止整个进程。
  /// 此处直连同一平台通道并改用显式 Windows VK 码，命令经 MusicMediaKeyBridge
  /// 转接音乐播放会话层注入的命令。
  ///
  /// 能力由 [PlatformCapabilities.supportsMediaKeys] 驱动（当前仅 Windows）。
  Future<void> registerMediaKeys() async {
    if (!PlatformCapabilities.current().supportsMediaKeys) {
      return;
    }
    _mediaKeyEventSub ??= _hotkeyEventChannel.receiveBroadcastStream().listen(
      _handleMediaKeyEvent,
    );
    await _registerMediaHotKey(
      identifier: 'omninest_media_play_pause',
      keyCode: _vkMediaPlayPause,
      onKeyDown: () {
        unawaited(MusicMediaKeyBridge.dispatchPlayPauseToggle());
      },
    );
    await _registerMediaHotKey(
      identifier: 'omninest_media_next',
      keyCode: _vkMediaNextTrack,
      onKeyDown: () {
        unawaited(MusicMediaKeyBridge.dispatch(play: false, next: true));
      },
    );
    await _registerMediaHotKey(
      identifier: 'omninest_media_previous',
      keyCode: _vkMediaPrevTrack,
      onKeyDown: () {
        unawaited(MusicMediaKeyBridge.dispatch(play: false, previous: true));
      },
    );
  }

  Future<void> _registerMediaHotKey({
    required String identifier,
    required int keyCode,
    required void Function() onKeyDown,
  }) async {
    await _hotkeyChannel.invokeMethod<void>('register', <String, Object>{
      'keyCode': keyCode,
      'identifier': identifier,
      'modifiers': <String>[],
    });
    _mediaKeyDownHandlers[identifier] = onKeyDown;
  }

  void _handleMediaKeyEvent(Object? event) {
    if (event is! Map) {
      return;
    }
    if (event['type'] != 'onKeyDown') {
      return;
    }
    final data = event['data'];
    if (data is! Map) {
      return;
    }
    final identifier = data['identifier'];
    if (identifier is! String) {
      return;
    }
    final handler = _mediaKeyDownHandlers[identifier];
    if (handler != null) {
      handler();
    }
  }

  /// 注销所有快捷键。
  Future<void> dispose() async {
    await _mediaKeyEventSub?.cancel();
    _mediaKeyEventSub = null;
    for (final identifier in _mediaKeyDownHandlers.keys.toList()) {
      await _hotkeyChannel.invokeMethod<void>('unregister', <String, Object>{
        'identifier': identifier,
      });
    }
    _mediaKeyDownHandlers.clear();
  }
}
