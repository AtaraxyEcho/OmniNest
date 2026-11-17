import 'dart:js_interop';

import 'package:web/web.dart' as web;

class FullscreenHelperWeb {
  FullscreenHelperWeb._();

  static bool _listenerBound = false;
  static final List<void Function(bool active)> _onChangeCallbacks =
      <void Function(bool active)>[];

  /// 绑定一次全局 fullscreenchange 监听，Web 实现内部使用。
  static void _ensureListener() {
    if (_listenerBound) {
      return;
    }
    _listenerBound = true;
    web.document.addEventListener(
      'fullscreenchange',
      ((web.Event event) {
        final active = isFullscreenEnabled;
        for (final callback in _onChangeCallbacks.toList(growable: false)) {
          callback(active);
        }
      }).toJS,
    );
  }

  /// 订阅 Web 全屏状态变化。
  static void addChangeListener(void Function(bool active) onChanged) {
    _ensureListener();
    _onChangeCallbacks.add(onChanged);
  }

  /// 取消订阅全屏状态变化。
  static void removeChangeListener(void Function(bool active) onChanged) {
    _onChangeCallbacks.remove(onChanged);
  }

  /// 进入全屏
  static void enterFullscreen(web.Element element) {
    element.requestFullscreen();
  }

  /// 退出全屏
  static void exitFullscreen() {
    web.document.exitFullscreen();
  }

  /// 切换全屏（如果当前全屏则退出，否则进入）
  static void toggleFullscreen(web.Element element) {
    if (isFullscreenEnabled) {
      exitFullscreen();
    } else {
      enterFullscreen(element);
    }
  }

  /// 当前是否处于全屏模式
  static bool get isFullscreenEnabled => web.document.fullscreenElement != null;

  /// 获取根元素（用于全屏）
  static web.Element get documentElement => web.document.documentElement!;
}
