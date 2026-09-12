import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 视频画中画（PiP）服务：仅 Android 实现有效，其它平台为空操作。
///
/// 播放页在进入/离开时标记 [setVideoPlaybackActive]；用户退后台时由
/// 原生侧决定是否进入 PiP，PiP 状态经 [pipModeChanged] 回调给 UI 精简。
class PipService {
  PipService._() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'pipChanged') {
        _pipMode = call.arguments == true;
        for (final listener in List<_PipListener>.of(_listeners)) {
          listener(_pipMode);
        }
      }
      return null;
    });
  }

  static const MethodChannel _channel = MethodChannel('omninest/pip');

  static PipService? _instance;

  final List<_PipListener> _listeners = <_PipListener>[];
  bool _pipMode = false;

  /// 当前是否处于 PiP 模式。
  bool get isInPipMode => _pipMode;

  static PipService instance() {
    return _instance ??= PipService._();
  }

  /// 标记视频播放页活跃：退后台时允许进入 PiP。
  Future<void> setVideoPlaybackActive({required bool active}) async {
    if (_isNotAndroid) {
      return;
    }
    try {
      await _channel.invokeMethod<bool>('setVideoPlaybackActive', {
        'active': active,
      });
    } on PlatformException {
      // 原生侧不可用时忽略（低版本系统/平台差异）。
    }
  }

  /// 订阅 PiP 模式变化，返回取消函数。
  VoidCallback addListener(void Function(bool inPipMode) listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  bool get _isNotAndroid =>
      kIsWeb || defaultTargetPlatform != TargetPlatform.android;
}

typedef _PipListener = void Function(bool inPipMode);
