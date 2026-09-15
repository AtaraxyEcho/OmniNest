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

  /// 从页码更新（翻页模式）。
  ///
  /// 单页章节（totalPages <= 1）使用全书进度（章节在全书中的位置），
  /// 确保保存和显示的 chapterProgress 一致。
  void updateFromPage({
    required int localPageIndex,
    required int totalPages,
    required int charOffset,
    required String chapterId,
    int totalChapters = 0,
    int currentChapterIndex = 0,
  }) {
    double chapterProgress;
    if (totalPages > 1) {
      chapterProgress = (localPageIndex / (totalPages - 1)).clamp(0.0, 1.0);
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

  /// 序列化为 API payload。
  Map<String, dynamic> toPayload() => {
    'chapterId': _current.chapterId,
    'charOffset': _current.charOffset,
    'chapterProgress': _current.chapterProgress,
    'mode': _current.mode,
  };

  /// 从 API payload 恢复（兼容旧格式）。
  static ReaderPosition fromPayload(Map<String, dynamic> json) {
    // 新格式
    if (json.containsKey('charOffset')) {
      return ReaderPosition(
        chapterId: json['chapterId'] as String? ?? '',
        charOffset: (json['charOffset'] as num?)?.toInt() ?? 0,
        chapterProgress: (json['chapterProgress'] as num?)?.toDouble() ?? 0,
        mode: json['mode'] as String? ?? 'scroll',
      );
    }
    // 旧格式：滚动模式（blockIndex → charOffset 兼容）
    if (json.containsKey('scrollOffset')) {
      final offset = (json['scrollOffset'] as num?)?.toDouble() ?? 0;
      final maxExtent = (json['maxScrollExtent'] as num?)?.toDouble() ?? 1;
      final ratio = maxExtent > 0 ? (offset / maxExtent).clamp(0.0, 1.0) : 0.0;
      return ReaderPosition(
        chapterId: json['chapterId'] as String? ?? '',
        charOffset: 0,
        chapterProgress: ratio,
        mode: 'scroll',
      );
    }
    // 旧格式：翻页模式
    if (json.containsKey('page')) {
      final page = (json['page'] as num?)?.toInt() ?? 0;
      final totalPages = (json['totalPages'] as num?)?.toInt() ?? 1;
      final ratio =
          totalPages > 1 ? (page / (totalPages - 1)).clamp(0.0, 1.0) : 0.0;
      return ReaderPosition(
        chapterId: json['chapterId'] as String? ?? '',
        charOffset: 0,
        chapterProgress: ratio,
        mode: 'page',
      );
    }
    return ReaderPosition(chapterId: json['chapterId'] as String? ?? '');
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
