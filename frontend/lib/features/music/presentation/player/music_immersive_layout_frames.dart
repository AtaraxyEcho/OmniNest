part of 'music_immersive_layout_spec.dart';

/// 单侧布局的框架：把样例的页边距、顶栏、主区与 12 列网格拆成可复用几何。
@immutable
class MusicSideLayoutFrame {
  const MusicSideLayoutFrame({
    required this.scale,
    required this.pagePadding,
    required this.headerTop,
    required this.headerHeight,
    required this.mainRect,
    required this.gridGap,
    required this.deckColumnWidth,
    required this.lyricColumnWidth,
  });

  /// 按基准尺寸推导的框架：[topPadding] 让出宿主自绘的顶部安全区，
  factory MusicSideLayoutFrame.resolve(
    Size size, {
    double? topPadding,
    double? headerHeight,
  }) {
    final scale = musicLayoutScale(size);
    final pagePadding = kMusicLayoutPagePadding * scale;
    final headerTop =
        math.max(pagePadding, topPadding ?? pagePadding).toDouble();
    final resolvedHeaderHeight =
        math
            .max(
              headerHeight ??
                  math.max(
                    kMusicLayoutHeaderBlockHeight * scale,
                    kMusicLayoutHeaderBlockMinHeight,
                  ),
              kMusicLayoutHeaderBlockMinHeight,
            )
            .toDouble();
    final gridGap = kMusicLayoutGridGap * scale;
    final mainTop = headerTop + resolvedHeaderHeight;
    final availableWidth =
        math.max(0.0, size.width - pagePadding * 2).toDouble();
    // 主舞台按样例 `main` 的 `max-w-6xl mx-auto` 限宽并水平居中：窗口比基准宽时
    // 两栏不摊满整窗，歌词向中部靠拢、卡组从窗口边缘回弹。
    final contentWidth =
        math.min(availableWidth, kMusicStageMaxWidth * scale).toDouble();
    final contentLeft = pagePadding + (availableWidth - contentWidth) / 2;
    // 主区底边固定在 `height - 13.5rem`，顶部安全区只把上沿下压。
    final desiredHeight =
        size.height -
        kMusicLayoutMainChrome * scale -
        (headerTop - pagePadding);
    final mainBottom = math.min(
      mainTop + math.max(240.0, desiredHeight),
      size.height - pagePadding,
    );
    final mainHeight = math.max(120.0, mainBottom - mainTop).toDouble();
    return MusicSideLayoutFrame(
      scale: scale,
      pagePadding: pagePadding,
      headerTop: headerTop,
      headerHeight: resolvedHeaderHeight,
      mainRect: Rect.fromLTWH(contentLeft, mainTop, contentWidth, mainHeight),
      gridGap: gridGap,
      deckColumnWidth: musicLayoutColumns(
        contentWidth,
        kMusicLayoutDeckTracks,
        gridGap,
      ),
      lyricColumnWidth: musicLayoutColumns(
        contentWidth,
        kMusicLayoutLyricTracks,
        gridGap,
      ),
    );
  }

  final double scale;
  final double pagePadding;
  final double headerTop;
  final double headerHeight;
  final Rect mainRect;
  final double gridGap;
  final double deckColumnWidth;
  final double lyricColumnWidth;

  /// 卡组列：居左布局在左，居右布局在右。
  Rect deckSection(PortalMusicLayout layout) {
    if (layout == PortalMusicLayout.left) {
      return Rect.fromLTWH(
        mainRect.left,
        mainRect.top,
        deckColumnWidth,
        mainRect.height,
      );
    }
    return Rect.fromLTWH(
      mainRect.left + lyricColumnWidth + gridGap,
      mainRect.top,
      deckColumnWidth,
      mainRect.height,
    );
  }

  /// 歌词列：与卡组列对调。
  Rect lyricSection(PortalMusicLayout layout) {
    if (layout == PortalMusicLayout.left) {
      return Rect.fromLTWH(
        mainRect.left + deckColumnWidth + gridGap,
        mainRect.top,
        lyricColumnWidth,
        mainRect.height,
      );
    }
    return Rect.fromLTWH(
      mainRect.left,
      mainRect.top,
      lyricColumnWidth,
      mainRect.height,
    );
  }

  /// 歌词列的内容矩形：扣掉样例列内边距，再让出顶部元信息行与底部锚点行。
  Rect lyricViewport(PortalMusicLayout layout) {
    final section = lyricSection(layout);
    final padding =
        layout == PortalMusicLayout.right
            ? kMusicRightLyricPadding
            : kMusicLeftLyricPadding;
    final footerHeight =
        layout == PortalMusicLayout.right
            ? kMusicRightLyricFooterHeight
            : kMusicLeftLyricFooterHeight;
    final left = section.left + padding.left * scale;
    final right = section.right - padding.right * scale;
    final top = section.top + kMusicLyricMetaRowHeight * scale;
    final bottom = section.bottom - footerHeight * scale;
    return Rect.fromLTRB(
      left,
      top,
      math.max(left, right),
      math.max(top, bottom),
    );
  }
}

/// 卡组容器几何：容器矩形与透视距离。
@immutable
class MusicDeckStageGeometry {
  const MusicDeckStageGeometry({required this.rect, required this.perspective});

  /// 解析两侧布局的卡组容器。
  factory MusicDeckStageGeometry.resolveSide({
    required PortalMusicLayout layout,
    required Rect sectionRect,
    required double scale,
    double trailingHeight = 0,
  }) {
    final stage = musicDeckStageSize(layout);
    final inset = 24 * scale;
    final available = math.max(0.0, sectionRect.width - inset).toDouble();
    final stageWidth = math.min(stage.width * scale, available).toDouble();
    final stageHeight =
        math.min(stage.height * scale, sectionRect.height).toDouble();
    final left =
        layout == PortalMusicLayout.right
            ? sectionRect.right - inset - stageWidth
            : sectionRect.left + inset;
    return MusicDeckStageGeometry(
      rect: Rect.fromLTWH(
        left,
        // 样例的卡组列纵向居中「舞台 + 尾部元素」，只居中舞台会让卡组偏低。
        sectionRect.top +
            (sectionRect.height - stageHeight - trailingHeight) / 2,
        stageWidth,
        stageHeight,
      ),
      perspective: musicDeckPerspective(layout) * scale,
    );
  }

  /// 解析居中布局的卡组容器（`max-w-5xl h-[380px]`，在内容区居中）。
  factory MusicDeckStageGeometry.resolveCenter({
    required Rect contentRect,
    required double top,
    required double height,
    required double scale,
  }) {
    final stageWidth =
        math
            .min(kMusicCenterDeckMaxWidth * scale, contentRect.width)
            .toDouble();
    return MusicDeckStageGeometry(
      rect: Rect.fromLTWH(
        contentRect.left + (contentRect.width - stageWidth) / 2,
        top,
        stageWidth,
        height,
      ),
      perspective: kMusicCenterPerspective * scale,
    );
  }

  final Rect rect;
  final double perspective;
}

/// 居中布局的整体框架：卡组、曲目信息、歌词窗口三段纵向串联并整体居中。
@immutable
class MusicCenterLayoutFrame {
  const MusicCenterLayoutFrame({
    required this.scale,
    required this.deck,
    required this.metaRect,
    required this.lyricRect,
    required this.headerTop,
    required this.headerHeight,
  });

  /// 按基准尺寸推导居中布局。
  ///
  /// [deckEnabled] 为 false 时（用户关闭堆叠卡片）跳过卡组与曲目信息带，
  /// 歌词改为通高滚动视口：元信息带贴内容区顶部，视口吃满剩余高度，
  /// 当前句位置由用户的焦点锚点决定，不再靠固定窗口高度居中。
  /// [lyricHeaderHeight] 为歌词窗口上方元信息带预留高度（居右布局样例）。
  /// [lyricSlotHeight] 与 [lyricWindowLines] 用于按实际行槽推导固定窗口高度。
  factory MusicCenterLayoutFrame.resolve(
    Size size, {
    double? topPadding,
    double? headerHeight,
    bool deckEnabled = true,
    double lyricHeaderHeight = 0,
    required double lyricSlotHeight,
    required int lyricWindowLines,
  }) {
    final scale = musicLayoutScale(size);
    final pagePadding = kMusicLayoutPagePadding * scale;
    final headerTop =
        math.max(pagePadding, topPadding ?? pagePadding).toDouble();
    final resolvedHeaderHeight =
        math
            .max(
              headerHeight ??
                  math.max(
                    kMusicLayoutHeaderBlockHeight * scale,
                    kMusicLayoutHeaderBlockMinHeight,
                  ),
              kMusicLayoutHeaderBlockMinHeight,
            )
            .toDouble();
    // 底部播放条不是页面边距：留白只按页边距扣会把手势区压到播放条上。
    final footerReserved = kMusicCenterFooterReservedHeight * scale;
    final contentRect = Rect.fromLTWH(
      pagePadding,
      headerTop + resolvedHeaderHeight,
      math.max(0.0, size.width - pagePadding * 2).toDouble(),
      math
          .max(
            0.0,
            size.height -
                headerTop -
                resolvedHeaderHeight -
                pagePadding -
                footerReserved,
          )
          .toDouble(),
    );
    // 内容区按样例限制在 max-w-6xl 内水平居中。
    final contentMaxWidth =
        math.min(kMusicStageMaxWidth * scale, contentRect.width).toDouble();
    final centeredContent = Rect.fromLTWH(
      contentRect.left + (contentRect.width - contentMaxWidth) / 2,
      contentRect.top,
      contentMaxWidth,
      contentRect.height,
    );
    final lyricWidth = math.min(576 * scale, centeredContent.width).toDouble();
    final lyricLeft =
        centeredContent.left + (centeredContent.width - lyricWidth) / 2;
    if (!deckEnabled) {
      // 无卡组：元信息带贴内容区顶部，歌词滚动视口吃满其余高度。
      final viewportTop = centeredContent.top + lyricHeaderHeight;
      return MusicCenterLayoutFrame(
        scale: scale,
        deck: MusicDeckStageGeometry.resolveCenter(
          contentRect: centeredContent,
          top: viewportTop,
          height: 0,
          scale: scale,
        ),
        metaRect: Rect.zero,
        lyricRect: Rect.fromLTWH(
          lyricLeft,
          viewportTop,
          lyricWidth,
          math.max(0.0, centeredContent.height - lyricHeaderHeight).toDouble(),
        ),
        headerTop: headerTop,
        headerHeight: resolvedHeaderHeight,
      );
    }
    // 窗口过矮时卡组容器跟随收缩，保证曲目信息与歌词窗口仍在窗口内。
    final deckHeight =
        math
            .min(kMusicCenterDeckHeight * scale, centeredContent.height * 0.6)
            .toDouble();
    final deckGap = kMusicCenterDeckGap * scale;
    final metaHeight = 52 * scale;
    // 固定窗口按实际行槽推导：行槽取整留了 2px 余量（见
    // _MusicLyricsLayout.contentSlotHeight），窗口短于 lines * 行槽就会被
    // floor 掉一行，偶数行会让当前句偏离正中。
    final lyricHeight = math.max(1, lyricWindowLines) * (lyricSlotHeight + 2);
    final stackHeight = deckHeight + deckGap + metaHeight + lyricHeight;
    final top =
        centeredContent.top +
        math.max(0.0, (centeredContent.height - stackHeight) / 2).toDouble();
    final deck = MusicDeckStageGeometry.resolveCenter(
      contentRect: centeredContent,
      top: top,
      height: deckHeight,
      scale: scale,
    );
    return MusicCenterLayoutFrame(
      scale: scale,
      deck: deck,
      metaRect: Rect.fromLTWH(
        centeredContent.left,
        deck.rect.bottom + deckGap,
        centeredContent.width,
        metaHeight,
      ),
      lyricRect: Rect.fromLTWH(
        lyricLeft,
        deck.rect.bottom + deckGap + metaHeight,
        lyricWidth,
        lyricHeight,
      ),
      headerTop: headerTop,
      headerHeight: resolvedHeaderHeight,
    );
  }

  final double scale;
  final MusicDeckStageGeometry deck;
  final Rect metaRect;
  final Rect lyricRect;
  final double headerTop;
  final double headerHeight;
}
