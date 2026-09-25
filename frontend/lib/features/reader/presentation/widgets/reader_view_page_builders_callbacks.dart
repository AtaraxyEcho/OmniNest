part of 'reader_view_page_builders.dart';

class _ReaderLinkTarget {
  const _ReaderLinkTarget(this.chapterId, this.anchor);

  final String chapterId;
  final String? anchor;
}

/// 页面切换回调实现。
class PageTurnCallbacksImpl implements PageTurnCallbacks {
  PageTurnCallbacksImpl({
    required void Function(int) onPageChangedFn,
    required VoidCallback onPreviousChapterFn,
    required VoidCallback onNextChapterFn,
    required VoidCallback onToggleControlsFn,
  }) : _onPageChangedFn = onPageChangedFn,
       _onPreviousChapterFn = onPreviousChapterFn,
       _onNextChapterFn = onNextChapterFn,
       _onToggleControlsFn = onToggleControlsFn;

  final void Function(int) _onPageChangedFn;
  final VoidCallback _onPreviousChapterFn;
  final VoidCallback _onNextChapterFn;
  final VoidCallback _onToggleControlsFn;

  @override
  void onPageChanged(int pageIndex) => _onPageChangedFn(pageIndex);

  @override
  void onPreviousChapter() => _onPreviousChapterFn();

  @override
  void onNextChapter() => _onNextChapterFn();

  @override
  void onToggleControls() => _onToggleControlsFn();
}
