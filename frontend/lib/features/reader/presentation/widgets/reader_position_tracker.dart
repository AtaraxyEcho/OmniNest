/// 阅读位置数据模型。
///
/// 使用 charOffset（章节内字符偏移）存储位置，
/// 确保跨模式、跨设备、字号变化后位置稳定。
class ReaderPosition {
  final String chapterId;
  final int charOffset;
  final double chapterProgress;
  final String mode;

  const ReaderPosition({
    required this.chapterId,
    this.charOffset = 0,
    this.chapterProgress = 0,
    this.mode = 'scroll',
  });
}

/// 阅读位置追踪器。
///
/// 进度的唯一真相源。滚动模式和翻页模式共用同一套 charOffset 追踪。
class ReaderPositionTracker {
  ReaderPosition _current = const ReaderPosition(chapterId: '');

  /// 从滚动位置更新（滚动模式）。
  ///
  /// [charOffset] 由调用方通过累积块高度精确计算（contentLoader.scrollOffsetToCharOffset），
  /// 不再内部用比例近似，保证与 charOffsetToPixelOffset 互为逆运算。
  void updateFromScroll({
    required double offset,
    required double maxExtent,
    required int totalChars,
    required String chapterId,
    int? charOffset,
  }) {
    if (maxExtent <= 0 || totalChars <= 0) return;
    final ratio = (offset / maxExtent).clamp(0.0, 1.0);
    final effectiveCharOffset =
        charOffset ?? (ratio * totalChars).round().clamp(0, totalChars);
    // chapterProgress 从 charOffset 推导，确保一致性
    final progress =
        totalChars > 0
            ? (effectiveCharOffset / totalChars).clamp(0.0, 1.0)
            : ratio;
    _current = ReaderPosition(
      chapterId: chapterId,
      charOffset: effectiveCharOffset,
      chapterProgress: progress,
      mode: 'scroll',
    );
  }

  /// 从当前页起始字符偏移更新（翻页模式）。
  ///
  /// 懒分页不预知总页数，因此进度只能用字符口径，与 [updateFromScroll]
  /// 保持一致，两种模式的 chapterProgress 才可比。空章节（totalChars<=0）
  /// 退到全书位置，避免任何章节都报 0。
  ///
  /// 旧实现要求调用方传总页数，而唯一调用方传的是占位值 10000，
  /// 于是 chapterProgress 恒为 pageIndex/9999≈0，与同处写入的
  /// scrollProgress 口径分裂。
  void updateFromPage({
    required int charOffset,
    required String chapterId,
    int totalChars = 0,
    int totalChapters = 0,
    int currentChapterIndex = 0,
  }) {
    final double chapterProgress;
    if (totalChars > 0) {
      chapterProgress = (charOffset / totalChars).clamp(0.0, 1.0);
    } else {
      chapterProgress =
          totalChapters > 1
              ? (currentChapterIndex / (totalChapters - 1)).clamp(0.0, 1.0)
              : 0.0;
    }
    _current = ReaderPosition(
      chapterId: chapterId,
      charOffset: charOffset,
      chapterProgress: chapterProgress,
      mode: 'page',
    );
  }

  /// 直接设置 charOffset（用于进度恢复时初始化 tracker）。
  void setCharOffset(int charOffset, String chapterId) {
    _current = ReaderPosition(
      chapterId: chapterId,
      charOffset: charOffset,
      chapterProgress: _current.chapterProgress,
      mode: _current.mode,
    );
  }

  double get chapterProgress => _current.chapterProgress;
  String get chapterId => _current.chapterId;
  int get charOffset => _current.charOffset;
}
