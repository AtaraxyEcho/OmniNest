part of 'reader_view_page_builders.dart';

/// 「返回原进度」浮动控件构建。
extension ReaderViewPageBuildersReturn on ReaderViewPageBuilders {
  Widget buildReturnToProgressControl() {
    final l10n = AppLocalizations.of(context);
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom;
    final bottomOffset =
        showControls ? 216.0 + bottomPadding : 16.0 + bottomPadding;
    return AnimatedPositioned(
      left: 0,
      right: 0,
      bottom: bottomOffset,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: AnimatedOpacity(
        opacity: showReturnControl ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: ReaderReturnToProgressControl(
          settings: settings,
          label: l10n.readerReturnToProgress,
          onPressed: returnToOriginalProgress,
        ),
      ),
    );
  }
}
