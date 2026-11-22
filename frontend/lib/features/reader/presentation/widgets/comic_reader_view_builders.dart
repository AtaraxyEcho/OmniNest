part of 'comic_reader_view.dart';

/// 漫画阅读器的内容构建与单页/双页槽位装配。
extension _ComicReaderViewBuilders on ComicReaderViewState {
  /// 全舞台滚轮统一接管：注册 pointerSignalResolver 彻底阻止 InteractiveViewer 劫持普通滚轮。
  /// - 按住 Ctrl/Meta：执行焦点缩放；
  /// - 未按 Ctrl/Meta 且未放大（!_imageZoomed）：执行 320ms 节流翻页（兼容 dx/dy）；
  /// - 未按 Ctrl/Meta 且已放大：静默消费事件，防止误缩放或误翻页。
  void _handleComicPointerSignal(
    PointerSignalEvent event,
    int slotIndex,
    Size slotSize, {
    BuildContext? viewportContext,
  }) {
    if (event is! PointerScrollEvent) return;
    final hardware = HardwareKeyboard.instance;
    final isZoomModifier = hardware.isControlPressed || hardware.isMetaPressed;
    final dx = event.scrollDelta.dx;
    final dy = event.scrollDelta.dy;
    final primaryDelta = dy.abs() >= dx.abs() ? dy : dx;
    Offset? viewportFocal;
    final renderObj = viewportContext?.findRenderObject();
    if (renderObj is RenderBox && renderObj.hasSize) {
      viewportFocal = renderObj.globalToLocal(event.position);
    }

    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      if (!mounted) return;
      if (isZoomModifier) {
        _handleCtrlWheelZoom(
          event,
          slotIndex,
          slotSize,
          focalPoint: viewportFocal,
        );
        return;
      }
      if (_imageZoomed) return;
      if (primaryDelta.abs() < 24) return;
      final now = DateTime.now();
      final last = _lastWheelAt;
      if (last != null &&
          now.difference(last) < ComicReaderViewState._wheelThrottle) {
        return;
      }
      _lastWheelAt = now;
      _turnSlotByDelta(primaryDelta > 0 ? 1 : -1);
    });
  }

  /// 构建漫画内容。
  Widget _buildContent({
    required List<_ComicSpreadSlot> slots,
    required int activeSlotIndex,
    required bool useSpread,
    required bool isBookmarked,
    required Color pageSurfaceBg,
  }) {
    if (_totalPages <= 0) {
      return Center(
        child: Text(
          AppLocalizations.of(context).readerNoContent,
          style: TextStyle(color: _settings.onSurfaceVariantColor),
        ),
      );
    }
    if (_readingMode == ComicReadingMode.scroll) {
      return ReaderTapDetector(
        onTap: _handleScrollContentTap,
        child: _buildScrollMode(pageSurfaceBg),
      );
    }
    if (_readingMode == ComicReadingMode.book) {
      return _buildBookMode(
        slots: slots,
        activeSlotIndex: activeSlotIndex,
        useSpread: useSpread,
        isBookmarked: isBookmarked,
        pageSurfaceBg: pageSurfaceBg,
      );
    }
    return _buildSwipeMode(
      slots: slots,
      activeSlotIndex: activeSlotIndex,
      useSpread: useSpread,
      isBookmarked: isBookmarked,
      pageSurfaceBg: pageSurfaceBg,
    );
  }

  /// 竖向连续滚动模式。
  Widget _buildScrollMode(Color pageSurfaceBg) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(
          constraints.maxWidth,
          constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : MediaQuery.sizeOf(context).height,
        );
        final layout = _resolveLayout(viewport);
        _layoutIndex.updateContentWidth(layout.contentWidth);
        return ListView.builder(
          controller: _scrollController,
          padding: EdgeInsets.symmetric(
            horizontal: layout.horizontalPadding,
            vertical: _displaySettings.pageGap,
          ),
          itemCount: _totalPages,
          itemBuilder: (context, index) {
            final page = _pages[index];
            return Center(
              child: SizedBox(
                width: layout.contentWidth,
                child: Padding(
                  padding: EdgeInsets.only(bottom: _displaySettings.pageGap),
                  child: ComicPageImage(
                    page: page,
                    itemId: widget.itemId,
                    surfaceColor: pageSurfaceBg,
                    layout: ComicPageImageLayout.continuous,
                    quarterTurns: _quarterTurnsForPage(page),
                    onIntrinsicSizeResolved: _onPageIntrinsicSizeResolved,
                    onLayout:
                        (pageIndex, height) => _onPageLayout(
                          pageIndex,
                          height + _displaySettings.pageGap,
                        ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Book 3D 仿真翻页模式：
  /// - 双页模式直接走 `ReaderPageView(spread: true, seamlessSpine: true, bookmarkOnLeft: _isRtl, fullSurfaceDrag: true)`，
  ///   将 `_ComicSpreadSlot` 映射为 `slots.length * 2` 虚拟叶序列，实现真半页 3D 卷翻、封面封里与宽图左右无缝拆分；
  /// - 单页模式使用 `ReaderSinglePageBookShell` 包裹精装书壳；
  /// - 整体接入 `InteractiveViewer` 缩放（放大 `> 1.02` 锁翻页拖拽交由平移，复位恢复）。
  Widget _buildBookMode({
    required List<_ComicSpreadSlot> slots,
    required int activeSlotIndex,
    required bool useSpread,
    required bool isBookmarked,
    required Color pageSurfaceBg,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(
          constraints.maxWidth,
          constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : MediaQuery.sizeOf(context).height,
        );
        final horizontalInset =
            viewport.width >= 960 ? 88.0 : (useSpread ? 32.0 : 16.0);
        final verticalInset =
            viewport.width >= 960 ? 52.0 : (useSpread ? 36.0 : 24.0);
        final availW = math.max(240.0, viewport.width - horizontalInset * 2);
        final availH = math.max(320.0, viewport.height - verticalInset * 2);
        final maxBookW = useSpread ? 1280.0 : 720.0;
        final targetAspect = useSpread ? 1.44 : 0.72;
        var bookW = math.min(availW, maxBookW);
        var bookH = bookW / targetAspect;
        if (bookH > availH) {
          bookH = availH;
          bookW = math.min(availW, bookH * targetAspect);
        }

        final imageFit = _resolveImageBoxFit();
        final deskBg = _controlSettings.bookDeskColor;
        final contentRevision = Object.hash(
          useSpread,
          _displaySettings.imageFit,
          _isRtl,
          _controlSettings.palette.id,
          pageSurfaceBg.toARGB32(),
          _rotationRevision,
          slots.length,
        );

        Widget buildLeafImage(
          int pageIndex, {
          required AlignmentGeometry alignment,
          required bool forSnapshot,
          BoxFit? fitOverride,
          String keySuffix = '',
        }) {
          final page = _pages[pageIndex];
          final tracker = forSnapshot ? _ComicSnapshotSlotTracker(1) : null;
          return Builder(
            builder:
                (leafContext) => ComicPageImage(
                  key: ValueKey(
                    'comic-book-page-${page.id}'
                    '$keySuffix'
                    '${forSnapshot ? '-snap' : ''}',
                  ),
                  page: page,
                  itemId: widget.itemId,
                  surfaceColor: pageSurfaceBg,
                  layout: ComicPageImageLayout.paged,
                  fit: fitOverride ?? imageFit,
                  alignment: alignment,
                  quarterTurns: _quarterTurnsForPage(page),
                  onIntrinsicSizeResolved:
                      forSnapshot ? null : _onPageIntrinsicSizeResolved,
                  onFirstFramePainted:
                      tracker == null
                          ? null
                          : () => tracker.markPainted(leafContext),
                ),
          );
        }

        /// 双页虚拟叶映射：`slotIndex = leafIndex ~/ 2`, `isSecondLeaf = leafIndex.isOdd`。
        Widget? buildSpreadLeaf(int leafIndex, {bool forSnapshot = false}) {
          if (leafIndex < 0) return null;
          final slotIndex = leafIndex ~/ 2;
          if (slotIndex < 0 || slotIndex >= slots.length) return null;
          final isSecondLeaf = leafIndex.isOdd;
          final slot = slots[slotIndex];
          if (slot.pageIndices.isEmpty) return null;

          // LTR: leaf(0) 在物理左叶、leaf(1) 在物理右叶；
          // RTL: ReaderPageView 将 idx 放物理右叶、idx+1 放物理左叶。
          final isPhysicalLeft = _isRtl ? isSecondLeaf : !isSecondLeaf;
          final spineAlignment =
              isPhysicalLeft ? Alignment.centerRight : Alignment.centerLeft;

          // 1. 宽图跨页槽：ClipRect + Align + FractionallySizedBox(widthFactor: 2.0) 无缝拆成左右两半。
          if (slot.isWideSpread) {
            final pageIndex = slot.pageIndices.first;
            return ClipRect(
              child: Align(
                alignment:
                    isPhysicalLeft
                        ? Alignment.centerLeft
                        : Alignment.centerRight,
                child: FractionallySizedBox(
                  widthFactor: 2.0,
                  heightFactor: 1.0,
                  child: buildLeafImage(
                    pageIndex,
                    alignment: Alignment.center,
                    fitOverride: imageFit,
                    forSnapshot: forSnapshot,
                    keySuffix: isPhysicalLeft ? '-wide-l' : '-wide-r',
                  ),
                ),
              ),
            );
          }

          // 2. 常规双页槽：leaf(0) 为第一页、leaf(1) 为第二页，向中缝贴合。
          if (slot.pageIndices.length == 2) {
            final pageIndex =
                isSecondLeaf ? slot.pageIndices[1] : slot.pageIndices[0];
            return buildLeafImage(
              pageIndex,
              alignment: spineAlignment,
              forSnapshot: forSnapshot,
            );
          }

          // 3. 封面槽（i == 0）或末尾落单单页槽：首读叶放主画面，对侧铺设柔和封里纸面。
          if (isSecondLeaf) {
            return _ComicEndpaperLeaf(
              surfaceColor: pageSurfaceBg,
              deskColor: deskBg,
              forSnapshot: forSnapshot,
            );
          }
          return buildLeafImage(
            slot.pageIndices.first,
            alignment: spineAlignment,
            forSnapshot: forSnapshot,
          );
        }

        /// 单页 Book 模式槽位：复用 `ReaderSinglePageBookShell` 精装书壳。
        Widget? buildSingleBookSlot(int slotIndex, {bool forSnapshot = false}) {
          if (slotIndex < 0 || slotIndex >= slots.length) return null;
          final slot = slots[slotIndex];
          if (slot.pageIndices.isEmpty) return null;
          final lastSlot = slots.length <= 1 ? 1 : slots.length - 1;
          final rawProgress = (slotIndex / lastSlot).clamp(0.0, 1.0);
          return ReaderSinglePageBookShell(
            surfaceColor: pageSurfaceBg,
            paperEdgeColor: _controlSettings.paperEdgeColor,
            deskColor: deskBg,
            progress: rawProgress,
            bookmarked: !forSnapshot && isBookmarked,
            bookmarkOnLeft: _isRtl,
            stackOnLeft: _isRtl,
            showPaperGrain: false,
            child: buildLeafImage(
              slot.pageIndices.first,
              alignment: Alignment.center,
              forSnapshot: forSnapshot,
            ),
          );
        }

        final pageView =
            useSpread
                ? ReaderPageView(
                  key: ValueKey('comic-book-spread-view-${widget.itemId}'),
                  turnMode: PageTurnMode.cover,
                  reverse: _isRtl,
                  dragEnabled: !_imageZoomed,
                  allowMouseDrag: true,
                  fullSurfaceDrag: true,
                  spread: true,
                  seamlessSpine: true,
                  bookmarkOnLeft: _isRtl,
                  deskColor: deskBg,
                  showPaperGrain: false,
                  surfaceColor: pageSurfaceBg,
                  paperEdgeColor: _controlSettings.paperEdgeColor,
                  bookmarked: isBookmarked,
                  controller: _pageTurnController,
                  prepareSnapshotPage:
                      (leafIndex) => _prepareComicSpreadLeafSnapshot(
                        leafIndex,
                        slots: slots,
                        bookLogicalWidth: bookW,
                      ),
                  contentRevision: contentRevision,
                  state: PagedState(
                    chapterId: widget.itemId,
                    pageIndex: activeSlotIndex * 2,
                    pageCount: slots.length * 2,
                    hasMore: false,
                  ),
                  pageBuilder: (leafIndex) => buildSpreadLeaf(leafIndex),
                  snapshotPageBuilder:
                      (leafIndex) =>
                          buildSpreadLeaf(leafIndex, forSnapshot: true),
                  callbacks: _ComicPageTurnCallbacks(
                    onPageChangedFn: (newLeafIndex) {
                      final newSlotIndex = newLeafIndex ~/ 2;
                      if (newSlotIndex < 0 || newSlotIndex >= slots.length) {
                        return;
                      }
                      _resetOffscreenSlotTransforms(newSlotIndex);
                      _onPageChanged(slots[newSlotIndex].startPageIndex);
                    },
                    onToggleControlsFn: _toggleControls,
                  ),
                )
                : ReaderPageView(
                  key: ValueKey('comic-book-single-view-${widget.itemId}'),
                  turnMode: PageTurnMode.cover,
                  reverse: _isRtl,
                  dragEnabled: !_imageZoomed,
                  allowMouseDrag: true,
                  fullSurfaceDrag: true,
                  spread: false,
                  seamlessSpine: true,
                  bookmarkOnLeft: _isRtl,
                  deskColor: deskBg,
                  showPaperGrain: false,
                  surfaceColor: pageSurfaceBg,
                  paperEdgeColor: _controlSettings.paperEdgeColor,
                  bookmarked: isBookmarked,
                  controller: _pageTurnController,
                  prepareSnapshotPage:
                      (slotIndex) => _prepareComicSingleSlotSnapshot(
                        slotIndex,
                        slots: slots,
                        slotLogicalWidth: bookW,
                      ),
                  contentRevision: contentRevision,
                  state: PagedState(
                    chapterId: widget.itemId,
                    pageIndex: activeSlotIndex,
                    pageCount: slots.length,
                    hasMore: false,
                  ),
                  pageBuilder: (slotIndex) => buildSingleBookSlot(slotIndex),
                  snapshotPageBuilder:
                      (slotIndex) =>
                          buildSingleBookSlot(slotIndex, forSnapshot: true),
                  callbacks: _ComicPageTurnCallbacks(
                    onPageChangedFn: (newSlotIndex) {
                      if (newSlotIndex < 0 || newSlotIndex >= slots.length) {
                        return;
                      }
                      _resetOffscreenSlotTransforms(newSlotIndex);
                      _onPageChanged(slots[newSlotIndex].startPageIndex);
                    },
                    onToggleControlsFn: _toggleControls,
                  ),
                );

        final zoomController = _controllerForSlot(activeSlotIndex);
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerSignal:
              (event) => _handleComicPointerSignal(
                event,
                activeSlotIndex,
                viewport,
                viewportContext: context,
              ),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onDoubleTapDown:
                (details) =>
                    _lastDoubleTapLocalPosition = details.localPosition,
            onDoubleTap: () => _toggleDoubleTapZoom(activeSlotIndex, viewport),
            child: InteractiveViewer(
              transformationController: zoomController,
              minScale: 1.0,
              maxScale: 4.0,
              panEnabled: _imageZoomed,
              scaleEnabled: true,
              onInteractionUpdate: (_) => _syncSlotZoomScale(activeSlotIndex),
              onInteractionEnd: (_) => _syncSlotZoomScale(activeSlotIndex),
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerSignal:
                    (event) => _handleComicPointerSignal(
                      event,
                      activeSlotIndex,
                      viewport,
                      viewportContext: context,
                    ),
                child: Center(
                  child: SizedBox(width: bookW, height: bookH, child: pageView),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Swipe 水平滑动模式：保留双页槽位、0px 无缝跨页与每页独立 `InteractiveViewer` 缩放。
  Widget _buildSwipeMode({
    required List<_ComicSpreadSlot> slots,
    required int activeSlotIndex,
    required bool useSpread,
    required bool isBookmarked,
    required Color pageSurfaceBg,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(
          constraints.maxWidth,
          constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : MediaQuery.sizeOf(context).height,
        );
        final layout = _resolveLayout(viewport);
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerSignal:
              (event) => _handleComicPointerSignal(
                event,
                activeSlotIndex,
                viewport,
                viewportContext: context,
              ),
          child: ReaderPageView(
            key: ValueKey('comic-swipe-view-${widget.itemId}'),
            turnMode: PageTurnMode.slide,
            reverse: _isRtl,
            dragEnabled: !_imageZoomed,
            allowMouseDrag: true,
            spread: false,
            showPaperGrain: false,
            surfaceColor: pageSurfaceBg,
            paperEdgeColor: _controlSettings.paperEdgeColor,
            bookmarked: isBookmarked,
            controller: _pageTurnController,
            contentRevision: Object.hash(
              useSpread,
              _displaySettings.imageFit,
              _isRtl,
              _controlSettings.palette.id,
              pageSurfaceBg.toARGB32(),
              _rotationRevision,
            ),
            state: PagedState(
              chapterId: widget.itemId,
              pageIndex: activeSlotIndex,
              pageCount: slots.length,
              hasMore: false,
            ),
            pageBuilder: (slotIndex) {
              if (slotIndex < 0 || slotIndex >= slots.length) return null;
              return _buildSlotPage(
                slotIndex: slotIndex,
                slot: slots[slotIndex],
                layout: layout,
                slotSize: viewport,
                pageSurfaceBg: pageSurfaceBg,
                interactive: true,
              );
            },
            snapshotPageBuilder: (slotIndex) {
              if (slotIndex < 0 || slotIndex >= slots.length) return null;
              return _buildSlotPage(
                slotIndex: slotIndex,
                slot: slots[slotIndex],
                layout: layout,
                slotSize: viewport,
                pageSurfaceBg: pageSurfaceBg,
                interactive: false,
              );
            },
            callbacks: _ComicPageTurnCallbacks(
              onPageChangedFn: (newSlotIndex) {
                if (newSlotIndex < 0 || newSlotIndex >= slots.length) return;
                _resetOffscreenSlotTransforms(newSlotIndex);
                _onPageChanged(slots[newSlotIndex].startPageIndex);
              },
              onToggleControlsFn: _toggleControls,
            ),
          ),
        );
      },
    );
  }

  /// 构建 Swipe 模式的单页或双页跨页内容（支持 LTR/RTL 拼合顺序、0px 无缝跨页、图片适应模式、旋转与独立缩放）。
  Widget _buildSlotPage({
    required int slotIndex,
    required _ComicSpreadSlot slot,
    required ComicReaderLayout layout,
    required Size slotSize,
    required Color pageSurfaceBg,
    required bool interactive,
  }) {
    final indices = slot.pageIndices;
    final orderedIndices =
        indices.length == 2 && _isRtl ? [indices[1], indices[0]] : indices;
    final imageFit = _resolveImageBoxFit();

    Widget buildFittedImage(
      int pageIndex, {
      AlignmentGeometry alignment = Alignment.center,
    }) {
      final page = _pages[pageIndex];
      return ComicPageImage(
        key: ValueKey('comic-swipe-page-${page.id}'),
        page: page,
        itemId: widget.itemId,
        surfaceColor: pageSurfaceBg,
        layout: ComicPageImageLayout.paged,
        fit: imageFit,
        alignment: alignment,
        quarterTurns: _quarterTurnsForPage(page),
        onIntrinsicSizeResolved:
            interactive ? _onPageIntrinsicSizeResolved : null,
      );
    }

    final Widget composed =
        orderedIndices.length == 1
            ? buildFittedImage(orderedIndices.first)
            : Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: buildFittedImage(
                    orderedIndices[0],
                    alignment: Alignment.centerRight,
                  ),
                ),
                Expanded(
                  child: buildFittedImage(
                    orderedIndices[1],
                    alignment: Alignment.centerLeft,
                  ),
                ),
              ],
            );

    final padded = Padding(padding: layout.pagedPadding, child: composed);
    if (!interactive) {
      return ColoredBox(color: pageSurfaceBg, child: padded);
    }

    final controller = _controllerForSlot(slotIndex);
    return Builder(
      builder:
          (slotContext) => Listener(
            behavior: HitTestBehavior.translucent,
            onPointerSignal:
                (event) => _handleComicPointerSignal(
                  event,
                  slotIndex,
                  slotSize,
                  viewportContext: slotContext,
                ),
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onDoubleTapDown:
                  (details) =>
                      _lastDoubleTapLocalPosition = details.localPosition,
              onDoubleTap: () => _toggleDoubleTapZoom(slotIndex, slotSize),
              child: InteractiveViewer(
                transformationController: controller,
                minScale: 1.0,
                maxScale: 4.0,
                panEnabled: _imageZoomed,
                scaleEnabled: true,
                onInteractionUpdate: (_) => _syncSlotZoomScale(slotIndex),
                onInteractionEnd: (_) => _syncSlotZoomScale(slotIndex),
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerSignal:
                      (event) => _handleComicPointerSignal(
                        event,
                        slotIndex,
                        slotSize,
                        viewportContext: slotContext,
                      ),
                  child: padded,
                ),
              ),
            ),
          ),
    );
  }
}
