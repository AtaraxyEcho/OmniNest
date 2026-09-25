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
        (own.charOffset - snapshot.charOffset).abs() <= 64 &&
        (own.progress - snapshot.progress).abs() <= 0.002 &&
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
    noteOwnProgressSave(snapshot);
    unawaited(
      _progressSync.sync(
        itemId: widget.itemId,
        charOffset: snapshot.charOffset,
        progressPercent: snapshot.progress,
        readingMode: snapshot.mode,
        chapterId: snapshot.chapterId,
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

  /// 全书进度百分比（0.0-1.0），用于显示和同步。
  double get _bookProgress {
    final parsedBook = ref.read(parsedBookProvider(widget.itemId)).value;
    if (parsedBook == null || parsedBook.chapters.isEmpty) {
      return _scrollProgressNotifier.value.clamp(0.0, 1.0);
    }
    final chapterCharCounts =
        parsedBook.chapters.map((c) => c.charCount).toList();
    // 当前章节使用实际解析的 totalChars（与 parsedBook.charCount 可能因 HTML 标签不同）
    final chapterData = _contentLoader?.getByChapterId(_currentChapterId);
    final currentChapterIdx =
        _contentLoader?.allChapters.indexWhere(
          (c) => c.id == _currentChapterId,
        ) ??
        0;
    if (chapterData != null && currentChapterIdx < chapterCharCounts.length) {
      chapterCharCounts[currentChapterIdx] = chapterData.totalChars;
    }
    final totalBookChars = chapterCharCounts.fold<int>(0, (s, c) => s + c);
    if (totalBookChars <= 0) {
      return _scrollProgressNotifier.value.clamp(0.0, 1.0);
    }

    // 当前章节之前的字符数之和
    int previousChars = 0;
    for (
      var i = 0;
      i < currentChapterIdx && i < chapterCharCounts.length;
      i++
    ) {
      previousChars += chapterCharCounts[i];
    }
    // 当前章节内的字符数：直接用 tracker 的 charOffset，不依赖 _scrollProgress
    final chapterChars = chapterData?.totalChars ?? 0;
    final currentChapterChars = _positionTracker.charOffset.clamp(
      0,
      chapterChars,
    );

    return ((previousChars + currentChapterChars) / totalBookChars).clamp(
      0.0,
      1.0,
    );
  }
}
