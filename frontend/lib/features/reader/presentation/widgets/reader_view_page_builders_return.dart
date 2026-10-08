part of 'reader_view_page_builders.dart';

/// 「返回原进度」与「其他设备进度」浮动控件构建。
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

  /// 「其他设备停在本章 X%」提示：与返回原进度共用轨道，后者优先。
  Widget buildRemoteProgressCue() {
    final candidate = remoteProgressCandidate;
    final l10n = AppLocalizations.of(context);
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom;
    final bottomOffset =
        showControls ? 216.0 + bottomPadding : 16.0 + bottomPadding;
    final visible = showRemoteProgressCue && !showReturnControl;
    // 服务端快照不带章内比例，按本章字符数就地换算，避免提示恒显 0%。
    final totalChars =
        contentLoader?.get(currentChapterId, settings)?.totalChars ?? 0;
    double chapterRatio = 0.0;
    if (candidate != null) {
      if (candidate.chapterProgress > 0) {
        chapterRatio = candidate.chapterProgress;
      } else if (totalChars > 0) {
        chapterRatio = (candidate.charOffset / totalChars).clamp(0.0, 1.0);
      }
    }
    final percent = (chapterRatio * 100).round();
    return AnimatedPositioned(
      left: 0,
      right: 0,
      bottom: bottomOffset,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        // 淡出后的候选快照仍留在状态里，不可见时必须挡住点击，
        // 否则空按会把本机位置悄悄跳到远端进度。
        child: IgnorePointer(
          ignoring: !visible,
          child: ReaderReturnToProgressControl(
            settings: settings,
            label: l10n.readerSyncRemoteProgress('$percent%'),
            onPressed: jumpToRemoteProgress,
          ),
        ),
      ),
    );
  }
}
