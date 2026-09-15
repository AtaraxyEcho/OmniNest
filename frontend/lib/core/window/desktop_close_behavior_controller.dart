import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/window/desktop_close_action.dart';
import 'package:omninest/core/window/desktop_close_flow.dart';

/// 桌面端关闭窗口行为偏好（设备级）；null 表示每次关闭时询问。
final desktopCloseBehaviorProvider =
    AsyncNotifierProvider<DesktopCloseBehaviorController, DesktopCloseAction?>(
      DesktopCloseBehaviorController.new,
    );

class DesktopCloseBehaviorController
    extends AsyncNotifier<DesktopCloseAction?> {
  @override
  Future<DesktopCloseAction?> build() {
    return DesktopCloseFlow.instance.readRememberedAction();
  }

  Future<void> setAction(DesktopCloseAction? action) async {
    state = AsyncData(action);
    await DesktopCloseFlow.instance.rememberAction(action);
  }
}
