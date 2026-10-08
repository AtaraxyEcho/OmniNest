part of 'reader_view_page.dart';

/// 全书进度重算、回声判定与退出时强制上报。
extension _ReaderViewPageProgress on _ReaderViewPageState {
  /// 防抖重算全书进度（O 章节），滚动期间最多每 200ms 一次。
  void _scheduleBookProgressRecompute() {
    if (_bookProgressRecomputeTimer != null) {
      return;
    }
    final input = _scrollProgressNotifier.value;
    if ((input - _lastBookProgressInput).abs() < 0.0005) {
      return;
    }
    _bookProgressRecomputeTimer = Timer(const Duration(milliseconds: 200), () {
      _bookProgressRecomputeTimer = null;
      if (!mounted) {
        return;
      }
      // 切章/加载期间 tracker 仍是旧章偏移，此时重算会得到错误中间值；
      // 挂起重算，待加载完成后由 refreshBookProgressNow 一次到位。
      if (_isSwitchingChapter || _isLoadingChapter) {
        return;
      }
      _lastBookProgressInput = _scrollProgressNotifier.value;
      _bookProgressNotifier.value = _bookProgress;
    });
  }

  /// 判断服务端回灌的进度快照是否为本机刚保存的自身回声。
  ///
  /// 本机保存→服务端落库→详情 provider 刷新会产生一条与本地快照内容
  /// 相同、时间戳略新的记录；不跳过就会把刚保存的位置重新施加回 UI，
  /// 表现为每次滚动/点击后内容回跳"刷新"。跨设备更新时间必然晚于
  /// 本机保存时刻，不受影响。
  bool _isOwnProgressEcho(ReaderProgressSnapshot snapshot, DateTime at) {
    final own = _lastOwnProgressSave;
    final ownAt = own?.updatedAt;
    if (own == null || ownAt == null) {
      return false;
    }
    return own.chapterId == snapshot.chapterId &&
        (own.charOffset - snapshot.charOffset).abs() <=
            progressEchoCharTolerance &&
        ((own.bookProgress ?? 0) - (snapshot.bookProgress ?? 0)).abs() <=
            0.002 &&
        at.isBefore(ownAt.add(const Duration(seconds: 30)));
  }

  /// 退出阅读器时把当前记账强制上报服务端。
  ///
  /// 书级续读指针以服务端为准，常规上报按节流窗口执行：跳章后未再
  /// 产生滚动/翻页就退出时，指针仍停在跳章前的章节，下次打开会回退
  /// 到旧章。退出是强一致节点，必须在页面仍在树内（ref 可用）时发出
  /// 强制上报，不等待结果，不阻塞返回导航。
  void _syncProgressOnExit() {
    final snapshot = buildProgressSnapshot();
    if (snapshot == null) {
      return;
    }
    final bookProgress = snapshot.bookProgress;
    if (bookProgress == null) {
      // 全书口径未知：上报会写入误导性百分比，本地记账已经落盘。
      return;
    }
    noteOwnProgressSave(snapshot);
    unawaited(
      _progressSync.sync(
        itemId: widget.itemId,
        charOffset: snapshot.charOffset,
        progressPercent: bookProgress,
        readingMode: snapshot.mode,
        chapterId: snapshot.chapterId,
        manifestVersion: snapshot.manifestVersion,
      ),
    );
  }

  /// 当前章节标题，用于加载遮罩显示。
  String get _currentChapterTitle {
    // 优先从已加载的章节内容获取
    if (_cachedContent?.title.isNotEmpty == true) return _cachedContent!.title;
    // 从 contentLoader 获取
    final data = _contentLoader?.getByChapterId(_currentChapterId);
    if (data != null) return data.content.title;
    // 从章节列表获取
    final chapters = _contentLoader?.allChapters ?? [];
    final idx = chapters.indexWhere((c) => c.id == _currentChapterId);
    if (idx >= 0 && chapters[idx].title.isNotEmpty) return chapters[idx].title;
    return '';
  }

  /// 全书进度百分比（0.0-1.0）；null 表示从未算出过（清单尚未就绪）。
  double? get _bookProgress {
    final parsedBook = ref.read(parsedBookProvider(widget.itemId)).value;
    final chapterData = _contentLoader?.getByChapterId(_currentChapterId);
    final currentChapterIdx =
        _contentLoader?.allChapters.indexWhere(
          (c) => c.id == _currentChapterId,
        ) ??
        0;
    return resolveBookProgress(
      manifestCharCounts:
          parsedBook?.chapters.map((chapter) => chapter.charCount).toList(),
      currentChapterIndex: currentChapterIdx,
      paintedChapterChars: chapterData?.totalChars ?? 0,
      chapterOffsetChars: _positionTracker.charOffset,
      lastKnown: _bookProgressNotifier.value,
    );
  }
}

/// 全书进度读数：口径暂时无法确定时沿用最近一次已知值。
///
/// 与「未知不上报」是两件事：切章或尚未精测出本章字符数时，读数仍可用，
/// 常驻进度胶囊就不必掉回 0%；而真的从未算出过时返回 null，调用方跳过上报，
/// 绝不回退成章内比例。
double? resolveBookProgress({
  required List<int>? manifestCharCounts,
  required int currentChapterIndex,
  required int paintedChapterChars,
  required int chapterOffsetChars,
  required double? lastKnown,
}) {
  if (manifestCharCounts == null || manifestCharCounts.isEmpty) {
    return lastKnown;
  }
  return computeBookProgress(
        manifestCharCounts: manifestCharCounts,
        currentChapterIndex: currentChapterIndex,
        paintedChapterChars: paintedChapterChars,
        chapterOffsetChars: chapterOffsetChars,
      ) ??
      lastKnown;
}

/// 全书进度：分母恒为清单字符数，当前章按「章内比例 × 清单权重」计入。
///
/// 旧的写法把当前章的 painted 字符数写回权重数组，等于每打开一章就改掉分母：
/// EPUB 的清单 `charCount` 由服务端按 DOM 文本节点统计，与客户端折叠空白后的
/// painted 值本就不同口径，于是读数会随「翻开某章」而不是「读到某处」变化。
/// 章内比例本来就是 painted 空间内的相对量，乘回清单权重即可与分母同口径。
///
/// 返回 null 表示口径无法确定（清单缺失、当前章不在清单、本章还没测出字符数）。
/// 调用方必须跳过上报而不是回退成章内比例：章节比例作为全书比例上传会在
/// 读到任意长章章尾时被记成接近读完。
double? computeBookProgress({
  required List<int> manifestCharCounts,
  required int currentChapterIndex,
  required int paintedChapterChars,
  required int chapterOffsetChars,
}) {
  if (currentChapterIndex < 0 || paintedChapterChars <= 0) {
    return null;
  }
  final totalChars = manifestCharCounts.fold<int>(
    0,
    (sum, count) => sum + count,
  );
  if (manifestCharCounts.isEmpty || totalChars <= 0) {
    return null;
  }
  final index = currentChapterIndex.clamp(0, manifestCharCounts.length - 1);
  final chapterRatio = (chapterOffsetChars / paintedChapterChars).clamp(
    0.0,
    1.0,
  );
  var previousChars = 0;
  for (var i = 0; i < index; i++) {
    previousChars += manifestCharCounts[i];
  }
  final weighted = previousChars + manifestCharCounts[index] * chapterRatio;
  return (weighted / totalChars).clamp(0.0, 1.0);
}
