part of 'reader_view_page_mixin.dart';

/// 「返回原进度」浮动控件的显示与隐藏。
extension ReaderViewPageMixinReturn on ReaderViewPageMixin {
  /// 显示"返回原进度"浮动控件。
  void showReturnToProgressSnackBar() {
    if (!mounted) return;
    // 两个控件共用同一条底部轨道，后者覆盖前者而不是叠放。
    hideProgressJumpCue();
    returnControlTimer?.cancel();
    _updateState(() => showReturnControl = true);

    returnControlTimer = Timer(const Duration(seconds: 3), () {
      hideReturnControl();
    });
  }

  /// 隐藏"返回原进度"控件。
  void hideReturnControl() {
    if (!mounted) return;
    if (showReturnControl) {
      _updateState(() => showReturnControl = false);
    }
  }
}
