import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 音量键翻页方向：up=向前翻，down=向后翻。
enum ReaderVolumeKeyDirection { up, down }

/// 音量键翻页服务：仅 Android 实现有效，其它平台为空操作。
///
/// 阅读页开启后原生层拦截音量键并转发 onVolumeKey 回调，由阅读页
/// 映射为翻页命令；关闭或离开阅读页后恢复系统音量行为。
class ReaderVolumeKeyService {
  ReaderVolumeKeyService._() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onVolumeKey') {
        final direction =
            call.arguments == 'up'
                ? ReaderVolumeKeyDirection.up
                : ReaderVolumeKeyDirection.down;
        for (final listener in List<_VolumeKeyListener>.of(_listeners)) {
          listener(direction);
        }
      }
      return null;
    });
  }

  static const MethodChannel _channel = MethodChannel('omninest/reader_volume');

  static ReaderVolumeKeyService? _instance;

  final List<_VolumeKeyListener> _listeners = <_VolumeKeyListener>[];

  static ReaderVolumeKeyService instance() {
    return _instance ??= ReaderVolumeKeyService._();
  }

  /// 开启或关闭原生层音量键拦截。
  Future<void> setVolumeKeyPagingEnabled({required bool enabled}) async {
    if (_isNotAndroid) {
      return;
    }
    try {
      await _channel.invokeMethod<bool>('setEnabled', {'enabled': enabled});
    } on PlatformException {
      // 原生侧不可用时忽略（平台差异/引擎未就绪）。
    }
  }

  /// 订阅音量键翻页事件，返回取消订阅函数。
  VoidCallback addListener(
    void Function(ReaderVolumeKeyDirection direction) listener,
  ) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  bool get _isNotAndroid =>
      kIsWeb || defaultTargetPlatform != TargetPlatform.android;
}

typedef _VolumeKeyListener = void Function(ReaderVolumeKeyDirection direction);
