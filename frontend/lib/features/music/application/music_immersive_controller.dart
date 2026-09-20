import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 音乐沉浸层激活标志与退出路由。
///
/// 壳层顶栏据此做语境切换：音乐沉浸播放期间顶栏的门户「沉浸模式」
/// 按钮让位为「退出沉浸播放」（门户沉浸偏好与音乐沉浸层是两个不同
/// 特性，此前互不知晓导致按钮状态不同步且退出无效）。
///
/// 退出处理器由沉浸层自身注册（甲板本地覆盖与 /music/now-playing 路由
/// 两种形态共用 [MusicImmersiveOverlay] 的接线），未注册时调用方自行
/// 回退导航。
final musicImmersiveControllerProvider =
    NotifierProvider<MusicImmersiveController, bool>(
      MusicImmersiveController.new,
    );

class MusicImmersiveController extends Notifier<bool> {
  void Function()? _exitHandler;

  @override
  bool build() {
    ref.onDispose(() {
      _exitHandler = null;
    });
    return false;
  }

  /// 沉浸层激活；[exitHandler] 在请求退出时被调用（关闭覆盖层或弹出路由）。
  void activate(void Function() exitHandler) {
    _exitHandler = exitHandler;
    if (ref.mounted) {
      state = true;
    }
  }

  /// 沉浸层关闭（覆盖层 dispose 或路由弹出时调用）。
  /// 容器可能已随测试/页面先行销毁，此时仅清理处理器即可。
  void deactivate() {
    _exitHandler = null;
    if (ref.mounted) {
      state = false;
    }
  }

  /// 请求退出沉浸层；返回 false 表示当前无注册的沉浸层（调用方自行回退）。
  bool requestExit() {
    final handler = _exitHandler;
    if (handler == null) {
      return false;
    }
    handler();
    return true;
  }
}
