import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/music/domain/music_visualizer_preset.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_layout_spec.dart';

/// 样例基准画布：三份设计稿均按 1280×1024 构图。
const Size _reference = Size(1280, 1024);

/// 与舞台同序推导居中框：歌词规格给出行槽与固定窗口行数。
MusicCenterLayoutFrame _resolveCenterFrame(
  Size size, {
  bool deckEnabled = true,
  double lyricHeaderHeight = 0,
}) {
  final spec = resolveMusicLyricSpec(
    PortalMusicLayout.center,
    musicLayoutScale(size),
    deckEnabled: deckEnabled,
  );
  return MusicCenterLayoutFrame.resolve(
    size,
    deckEnabled: deckEnabled,
    lyricHeaderHeight: lyricHeaderHeight,
    lyricSlotHeight: spec.slotHeight(),
    lyricWindowLines: spec.fixedWindowLines,
  );
}

void main() {
  group('复刻基准', () {
    test('基准尺寸下缩放系数为 1', () {
      expect(musicLayoutScale(_reference), 1);
    });

    test('缩放系数取宽高两方向的较小比例，构图始终落在窗口内', () {
      expect(musicLayoutScale(const Size(2560, 1440)), closeTo(1.40625, 1e-9));
      expect(musicLayoutScale(const Size(800, 600)), closeTo(0.58594, 1e-4));

      const windows = <Size>[
        Size(1280, 1024),
        Size(3440, 1440),
        Size(1920, 1080),
        Size(1024, 768),
        Size(800, 600),
        Size(600, 900),
        Size(1280, 400),
        Size(320, 240),
      ];
      for (final window in windows) {
        final scale = musicLayoutScale(window);
        expect(
          scale * kMusicLayoutReferenceWidth,
          lessThanOrEqualTo(window.width + 1e-6),
          reason: '宽度方向不应溢出：$window',
        );
        expect(
          scale * kMusicLayoutReferenceHeight,
          lessThanOrEqualTo(window.height + 1e-6),
          reason: '高度方向不应溢出：$window',
        );
      }
    });

    test('窗口装不下两侧双列时退化为纵向串联构图', () {
      const wide = Size(1280, 1024);
      expect(
        resolveMusicComposition(wide, PortalMusicLayout.left),
        PortalMusicLayout.left,
      );
      expect(
        resolveMusicComposition(wide, PortalMusicLayout.right),
        PortalMusicLayout.right,
      );
      // 居中构图本身就是单列纵向串联，任何窗口都成立。
      expect(
        resolveMusicComposition(const Size(600, 900), PortalMusicLayout.center),
        PortalMusicLayout.center,
      );
      // 窗口过窄。
      expect(
        resolveMusicComposition(const Size(900, 700), PortalMusicLayout.left),
        PortalMusicLayout.center,
      );
      // 窗口过矮。
      expect(
        resolveMusicComposition(const Size(1600, 500), PortalMusicLayout.left),
        PortalMusicLayout.center,
      );
      // 窗口过于竖长（竖屏）。
      expect(
        resolveMusicComposition(
          const Size(1000, 1600),
          PortalMusicLayout.right,
        ),
        PortalMusicLayout.center,
      );
    });

    test('12 列网格列宽与样例一致', () {
      // grid-cols-12 gap-8：内容宽 1200，栏距 32。
      expect(musicLayoutColumns(1200, 5, 32), closeTo(481.33, 0.01));
      expect(musicLayoutColumns(1200, 7, 32), closeTo(686.67, 0.01));
    });
  });

  group('卡面复刻参数', () {
    test('居左布局为统一等距角的 3D 纵叠', () {
      final hero = resolveMusicDeckCard(PortalMusicLayout.left, 0);
      expect(hero.size, 320);
      expect(hero.offset, Offset.zero);
      expect(hero.depth, 0);
      expect(hero.rotateY, closeTo(-18 * math.pi / 180, 1e-9));
      expect(hero.rotateX, closeTo(12 * math.pi / 180, 1e-9));
      expect(hero.rotateZ, closeTo(-4 * math.pi / 180, 1e-9));
      expect(hero.scale, 1);
      expect(hero.opacity, 1);
      expect(hero.blur, 0);
      expect(hero.radius, 16);
      expect(hero.borderAlpha, closeTo(0.45, 1e-9));
      expect(hero.shadowOffset, const Offset(0, 32));
      expect(hero.shadowBlur, 70);
      expect(hero.shadowAlpha, closeTo(0.95, 1e-9));
      expect(hero.glowAlpha, greaterThan(0));

      final second = resolveMusicDeckCard(PortalMusicLayout.left, 1);
      expect(second.offset, const Offset(34, -22));
      expect(second.depth, -60);
      expect(second.scale, closeTo(0.94, 1e-9));
      expect(second.opacity, closeTo(0.92, 1e-9));
      expect(second.blur, closeTo(0.2, 1e-9));
      expect(second.borderAlpha, closeTo(0.28, 1e-9));
      expect(second.shadowOffset, const Offset(18, 26));
      expect(second.shadowBlur, 55);
      expect(second.shadowAlpha, closeTo(0.88, 1e-9));
      expect(second.glowAlpha, 0);

      final deepest = resolveMusicDeckCard(PortalMusicLayout.left, 4);
      expect(deepest.size, 320);
      expect(deepest.offset, const Offset(136, -88));
      expect(deepest.depth, -240);
      expect(deepest.scale, closeTo(0.76, 1e-9));
      expect(deepest.opacity, closeTo(0.62, 1e-9));
      expect(deepest.blur, 1);
      expect(deepest.borderAlpha, closeTo(0.15, 1e-9));
      expect(deepest.shadowOffset, const Offset(36, 32));
    });

    test('居右布局为 2D 阶梯错层且卡面逐档收缩', () {
      final hero = resolveMusicDeckCard(PortalMusicLayout.right, 0);
      expect(hero.size, 335);
      expect(hero.offset, Offset.zero);
      expect(hero.depth, 0);
      expect(hero.rotateX, 0);
      expect(hero.rotateY, 0);
      expect(hero.rotateZ, 0);
      expect(hero.scale, 1);
      expect(hero.radius, 16);
      expect(hero.borderAlpha, closeTo(0.4, 1e-9));
      expect(hero.shadowOffset, const Offset(0, 28));

      final second = resolveMusicDeckCard(PortalMusicLayout.right, 1);
      expect(second.size, 325);
      expect(second.offset, const Offset(38, -22));
      expect(second.rotateZ, closeTo(4.5 * math.pi / 180, 1e-9));
      expect(second.scale, closeTo(0.97, 1e-9));
      expect(second.opacity, closeTo(0.94, 1e-9));
      expect(second.borderAlpha, closeTo(0.28, 1e-9));

      final deepest = resolveMusicDeckCard(PortalMusicLayout.right, 4);
      expect(deepest.size, 310);
      expect(deepest.offset, const Offset(152, -88));
      expect(deepest.rotateZ, closeTo(18 * math.pi / 180, 1e-9));
      expect(deepest.scale, closeTo(0.88, 1e-9));
      expect(deepest.opacity, closeTo(0.72, 1e-9));
      expect(deepest.borderAlpha, closeTo(0.2, 1e-9));
      expect(deepest.shadowOffset, const Offset(34, 24));
    });

    test('居中布局为左右对称的扇形展开', () {
      final outerLeft = resolveMusicDeckCard(PortalMusicLayout.center, -2);
      expect(outerLeft.size, 260);
      expect(outerLeft.offset, const Offset(-230, -24));
      expect(outerLeft.rotateZ, closeTo(-12 * math.pi / 180, 1e-9));
      expect(outerLeft.scale, closeTo(0.82, 1e-9));
      expect(outerLeft.opacity, closeTo(0.75, 1e-9));
      expect(outerLeft.radius, 12);
      expect(outerLeft.borderAlpha, closeTo(0.2, 1e-9));

      final hero = resolveMusicDeckCard(PortalMusicLayout.center, 0);
      expect(hero.size, 310);
      expect(hero.offset, Offset.zero);
      expect(hero.rotateZ, 0);
      expect(hero.scale, 1);
      expect(hero.opacity, 1);
      expect(hero.radius, 16);
      expect(hero.borderAlpha, closeTo(0.32, 1e-9));

      final outerRight = resolveMusicDeckCard(PortalMusicLayout.center, 2);
      expect(outerRight.offset, const Offset(230, -24));
      expect(outerRight.rotateZ, closeTo(12 * math.pi / 180, 1e-9));
      expect(outerRight.scale, closeTo(0.82, 1e-9));
      expect(outerRight.opacity, closeTo(0.75, 1e-9));

      final innerLeft = resolveMusicDeckCard(PortalMusicLayout.center, -1);
      final innerRight = resolveMusicDeckCard(PortalMusicLayout.center, 1);
      expect(innerLeft.offset.dx, -innerRight.offset.dx);
      expect(innerLeft.rotateZ, -innerRight.rotateZ);
      expect(innerLeft.size, innerRight.size);
    });

    test('展开态按同一系数放大且比例不变', () {
      final base = resolveMusicDeckCard(PortalMusicLayout.right, 1);
      final zoomed = base.zoomed(1.08);
      expect(zoomed.size, closeTo(base.size * 1.08, 1e-9));
      expect(zoomed.offset, base.offset * 1.08);
      expect(zoomed.scale, base.scale);
      expect(zoomed.opacity, base.opacity);
    });
  });

  group('卡组与歌词列几何', () {
    test('卡组容器按样例尺寸与对齐方式落位', () {
      expect(musicDeckStageSize(PortalMusicLayout.left), const Size(440, 385));
      expect(musicDeckStageSize(PortalMusicLayout.right), const Size(420, 390));
      expect(
        musicDeckStageSize(PortalMusicLayout.center),
        const Size(1024, 380),
      );
      expect(
        musicDeckStageAlignment(PortalMusicLayout.left),
        Alignment.centerLeft,
      );
      expect(
        musicDeckStageAlignment(PortalMusicLayout.right),
        Alignment.centerLeft,
      );
      expect(
        musicDeckStageAlignment(PortalMusicLayout.center),
        Alignment.center,
      );
      expect(musicDeckStageInset(PortalMusicLayout.left), 8);
      expect(musicDeckStageInset(PortalMusicLayout.right), 12);
      expect(musicDeckStageInset(PortalMusicLayout.center), 0);
      expect(musicDeckPerspective(PortalMusicLayout.left), 1400);
      expect(musicDeckPerspective(PortalMusicLayout.right), 0);
      expect(musicDeckPerspective(PortalMusicLayout.center), 1000);
    });

    test('两侧布局框架与样例主舞台限宽一致', () {
      final frame = MusicSideLayoutFrame.resolve(_reference);
      expect(frame.pagePadding, 40);
      expect(frame.headerTop, 40);
      // 顶栏块 = 样例顶栏 48 + `my-2` 8，主区上沿因此落在样例的 96。
      expect(frame.headerHeight, 56);
      // 样例 `main` 为 `max-w-6xl mx-auto` + `gap-10 lg:gap-16`：
      // 1280 基准下主舞台收成 1152 并左右各留 64。
      expect(frame.gridGap, 64);
      expect(frame.mainRect.left, 64);
      expect(frame.mainRect.top, closeTo(96, 1e-9));
      expect(frame.mainRect.width, closeTo(1152, 1e-9));
      expect(frame.mainRect.height, closeTo(808, 1e-9));
      expect(frame.mainRect.right, closeTo(1216, 1e-9));
      expect(frame.deckColumnWidth, closeTo(442.67, 0.01));
      expect(frame.lyricColumnWidth, closeTo(645.33, 0.01));

      // 居左布局：卡组在左、歌词在右；居右布局对调。
      expect(frame.deckSection(PortalMusicLayout.left).left, closeTo(64, 1e-9));
      expect(
        frame.lyricSection(PortalMusicLayout.left).left,
        closeTo(570.67, 0.01),
      );
      expect(
        frame.deckSection(PortalMusicLayout.right).left,
        closeTo(773.33, 0.01),
      );
      expect(
        frame.lyricSection(PortalMusicLayout.right).left,
        closeTo(64, 1e-9),
      );
    });

    test('宽窗口下主舞台限宽居中，两栏不摊满整窗', () {
      // 2560×1440：缩放由高度决定（1.40625），主舞台取样例上限后居中。
      const window = Size(2560, 1440);
      final frame = MusicSideLayoutFrame.resolve(window);
      final stageMax = kMusicStageMaxWidth * frame.scale;
      final sideMargin = (window.width - stageMax) / 2 - frame.pagePadding;
      expect(frame.mainRect.width, closeTo(stageMax, 1e-6));
      // 两侧留出等宽的背景带，视线聚到中部。
      expect(
        frame.mainRect.left - frame.pagePadding,
        closeTo(sideMargin, 1e-6),
      );
      expect(
        window.width - frame.pagePadding - frame.mainRect.right,
        closeTo(sideMargin, 1e-6),
      );
      // 留出量必须显著大于零，否则限宽没有生效。
      expect(sideMargin, greaterThan(300));
    });

    test('歌词视口扣掉列内边距与元信息/锚点行', () {
      final frame = MusicSideLayoutFrame.resolve(_reference);
      final left = frame.lyricViewport(PortalMusicLayout.left);
      expect(left.left, closeTo(610.67, 0.01));
      expect(left.right, closeTo(1192, 1e-9));
      expect(left.top, closeTo(134, 1e-9));
      expect(left.bottom, closeTo(862, 1e-9));

      final right = frame.lyricViewport(PortalMusicLayout.right);
      // 居右布局的左内边距按用户要求提到 40（样例 `lg:pl-6` 是 24，但居右时
      // 歌词列贴着窗口左缘，24 的观感是「完全贴在左侧」）。
      expect(right.left, closeTo(104, 1e-9));
      expect(right.right, closeTo(693.33, 0.01));
      expect(right.bottom, closeTo(858, 1e-9));
    });

    test('卡组容器在列内按样例内边距与上限落位', () {
      final frame = MusicSideLayoutFrame.resolve(_reference);
      final left = MusicDeckStageGeometry.resolveSide(
        layout: PortalMusicLayout.left,
        sectionRect: frame.deckSection(PortalMusicLayout.left),
        scale: frame.scale,
      );
      expect(left.rect.left, closeTo(88, 1e-9));
      // 限宽后卡组列按样例的 `max-w-[420px]` 收紧，舞台宽度落在列内上限。
      expect(left.rect.width, closeTo(418.67, 0.01));
      expect(left.rect.height, closeTo(385, 1e-9));
      expect(left.rect.top, closeTo(307.5, 1e-9));
      expect(left.perspective, 1400);

      final right = MusicDeckStageGeometry.resolveSide(
        layout: PortalMusicLayout.right,
        sectionRect: frame.deckSection(PortalMusicLayout.right),
        scale: frame.scale,
      );
      expect(right.rect.right, closeTo(1192, 1e-9));
      expect(right.rect.width, closeTo(418.67, 0.01));
      expect(right.rect.top, closeTo(305, 1e-9));
      expect(right.perspective, 0);
    });

    test('居中布局卡组、曲目信息与三行歌词窗口纵向串联', () {
      final frame = _resolveCenterFrame(_reference);
      expect(frame.deck.rect.width, closeTo(1024, 1e-9));
      expect(frame.deck.rect.height, closeTo(380, 1e-9));
      expect(frame.lyricRect.width, closeTo(576, 1e-9));
      // 行槽 60 + 2 取整余量 × 3 行；写死 120 会被 floor 成 2 行。
      expect(frame.lyricRect.height, closeTo(186, 1e-9));
      expect(frame.lyricRect.center.dx, closeTo(640, 1e-9));
      expect(frame.metaRect.top, closeTo(frame.deck.rect.bottom + 20, 1e-9));
      expect(frame.lyricRect.top, closeTo(frame.metaRect.bottom, 1e-9));
      // 底部播放条（86 + 8）已从内容区扣除，歌词不得压上去。
      expect(
        frame.lyricRect.bottom,
        lessThanOrEqualTo(
          _reference.height -
              (kMusicLayoutPagePadding + kMusicCenterFooterReservedHeight),
        ),
      );
    });

    test('关闭卡组后歌词变为通高滚动视口并让出播放条', () {
      const headerHeight = kMusicLyricMetaRowHeight;
      final frame = _resolveCenterFrame(
        _reference,
        deckEnabled: false,
        lyricHeaderHeight: headerHeight,
      );
      // 视口顶部贴在元信息带之下，底部到播放条上沿为止。
      expect(frame.lyricRect.top, greaterThanOrEqualTo(headerHeight));
      expect(
        frame.lyricRect.bottom,
        closeTo(
          _reference.height -
              (kMusicLayoutPagePadding + kMusicCenterFooterReservedHeight),
          1e-9,
        ),
      );
      // 通高视口远大于三行窗口，形态改为滚动。
      expect(frame.lyricRect.height, greaterThan(600));
      expect(frame.deck.rect.height, 0);
      expect(frame.metaRect, Rect.zero);
    });

    test('关闭卡组时歌词形态与两侧滚动布局同一口径', () {
      final scrolled = resolveMusicLyricSpec(
        PortalMusicLayout.center,
        1,
        deckEnabled: false,
      );
      final fixed = resolveMusicLyricSpec(PortalMusicLayout.center, 1);
      expect(scrolled.fixedWindowLines, 0);
      expect(scrolled.textAlign, TextAlign.left);
      expect(scrolled.blockAnchor, Alignment.centerLeft);
      expect(scrolled.mask, kMusicLeftLyricMask);
      // 滚动形态的行距与在读行样式跟两侧同一口径，否则在小窗度量下会挤成一块。
      expect(scrolled.lineGap, 18);
      expect(scrolled.activeLineBackgroundColor, isNotNull);
      expect(scrolled.activeLinePaddingY, greaterThan(0));
      expect(scrolled.activeLineScale, 1);
      // 卡组可见时仍是固定三行居中窗口。
      expect(fixed.fixedWindowLines, 3);
      expect(fixed.textAlign, TextAlign.center);
      expect(fixed.mask, kMusicCenterLyricMask);
      expect(fixed.lineGap, 12);
      expect(fixed.activeLineBackgroundColor, isNull);
      expect(fixed.activeLinePaddingY, 0);
      expect(fixed.activeLineScale, closeTo(1.04, 1e-9));
    });

    test('两种构图在各窗口尺寸下都不越出窗口', () {
      const windows = <Size>[
        Size(1280, 1024),
        Size(3440, 1440),
        Size(1024, 768),
        Size(960, 560),
        Size(800, 600),
        Size(600, 900),
        Size(420, 320),
      ];
      for (final window in windows) {
        final center = _resolveCenterFrame(window);
        expect(
          center.lyricRect.bottom,
          lessThanOrEqualTo(window.height + 1e-6),
          reason: '居中构图高度越界：$window',
        );
        expect(
          center.lyricRect.right,
          lessThanOrEqualTo(window.width + 1e-6),
          reason: '居中构图宽度越界：$window',
        );
        expect(center.deck.rect.top, greaterThanOrEqualTo(0));
        // 关闭卡组的滚动视口同样不得压到播放条上。
        final scrolled = _resolveCenterFrame(
          window,
          deckEnabled: false,
          lyricHeaderHeight:
              kMusicLyricMetaRowHeight * musicLayoutScale(window),
        );
        expect(
          scrolled.lyricRect.bottom,
          lessThanOrEqualTo(window.height + 1e-6),
          reason: '关卡组滚动视口越界：$window',
        );
        expect(
          scrolled.lyricRect.right,
          lessThanOrEqualTo(window.width + 1e-6),
          reason: '关卡组滚动视口宽度越界：$window',
        );
        expect(
          scrolled.lyricRect.bottom,
          lessThanOrEqualTo(
            window.height -
                (kMusicLayoutPagePadding + kMusicCenterFooterReservedHeight) *
                    musicLayoutScale(window) +
                1e-6,
          ),
          reason: '关卡组滚动视口压到播放条：$window',
        );

        if (resolveMusicComposition(window, PortalMusicLayout.left) !=
            PortalMusicLayout.left) {
          continue;
        }
        final side = MusicSideLayoutFrame.resolve(window);
        final deckStage = MusicDeckStageGeometry.resolveSide(
          layout: PortalMusicLayout.left,
          sectionRect: side.deckSection(PortalMusicLayout.left),
          scale: side.scale,
        );
        final lyricViewport = side.lyricViewport(PortalMusicLayout.left);
        expect(
          side.mainRect.bottom,
          lessThanOrEqualTo(window.height + 1e-6),
          reason: '两侧构图高度越界：$window',
        );
        expect(
          deckStage.rect.width,
          lessThanOrEqualTo(
            side.deckSection(PortalMusicLayout.left).width + 1e-6,
          ),
          reason: '卡组容器超出卡组列：$window',
        );
        expect(
          lyricViewport.right,
          lessThanOrEqualTo(window.width + 1e-6),
          reason: '歌词视口宽度越界：$window',
        );
        expect(
          lyricViewport.bottom,
          greaterThan(lyricViewport.top),
          reason: '歌词视口高度必须为正：$window',
        );
      }
    });
  });

  group('歌词复刻参数', () {
    test('两侧布局的字号、行距与渐隐区间取自样例', () {
      final left = resolveMusicLyricSpec(PortalMusicLayout.left, 1);
      expect(left.fontSize, 18);
      expect(left.activeFontSize, 44);
      expect(left.translationFontSize, 12);
      expect(left.activeTranslationFontSize, 16);
      expect(left.lineGap, 18);
      expect(left.mask, (0.14, 0.84));
      expect(left.textAlign, TextAlign.left);
      expect(left.blockAnchor, Alignment.centerLeft);
      expect(left.fixedWindowLines, 0);
      expect(left.activeLineScale, 1);

      final right = resolveMusicLyricSpec(PortalMusicLayout.right, 1);
      expect(right.fontSize, 18);
      expect(right.activeFontSize, 44);
      expect(right.lineGap, 20);
      expect(right.mask, (0.15, 0.82));
    });

    test('在读行时间标签默认关闭，开启后只在两侧布局预留', () {
      // 默认（未开启）：三项占位全部为 0，行槽与不渲染时一致。
      final off = resolveMusicLyricSpec(PortalMusicLayout.left, 1);
      expect(off.activeAuxGap, 0);
      expect(off.activeAuxReserve, 0);
      expect(off.activeAuxFontSize, 0);
      expect(off.activeAuxIconSize, 0);
      expect(off.activeAuxMinBlockWidth, 0);

      final left = resolveMusicLyricSpec(
        PortalMusicLayout.left,
        1,
        timeTagEnabled: true,
      );
      // 样例 `lyric-meta`：`mt-3` 间隙 + `py-1` 胶囊 + `text-[11px]` 文字。
      expect(left.activeAuxGap, 12);
      expect(left.activeAuxReserve, 22);
      expect(left.activeAuxFontSize, 11);
      expect(left.activeAuxIconSize, 12);
      expect(left.activeAuxMinBlockWidth, 124);
      expect(
        resolveMusicLyricSpec(
          PortalMusicLayout.right,
          1,
          timeTagEnabled: true,
        ).activeAuxReserve,
        22,
      );
      // 居中构图（固定三行窗口与关卡组滚动列）都不放这一行。
      final center = resolveMusicLyricSpec(
        PortalMusicLayout.center,
        1,
        timeTagEnabled: true,
      );
      expect(center.activeAuxGap, 0);
      expect(center.activeAuxReserve, 0);
      expect(center.activeAuxMinBlockWidth, 0);
      // 占位随缩放同比放大，行槽等高因此每行都计入。
      final scaled = resolveMusicLyricSpec(
        PortalMusicLayout.left,
        2,
        timeTagEnabled: true,
      );
      expect(scaled.activeAuxReserve, 44);
    });

    test('行距倍率只缩放块间隙，不缩在读行的底衬内边距', () {
      final tightened = resolveMusicLyricSpec(
        PortalMusicLayout.left,
        1,
        lineSpacing: 0.5,
      );
      expect(tightened.lineGap, 9);
      expect(tightened.activeLinePaddingY, isNot(0));
      // 设备缩放与行距倍率相乘。
      expect(
        resolveMusicLyricSpec(
          PortalMusicLayout.left,
          0.5,
          lineSpacing: 2,
        ).lineGap,
        18,
      );
    });

    test('居中布局卡组可见时为固定三行窗口', () {
      final center = resolveMusicLyricSpec(PortalMusicLayout.center, 1);
      expect(center.fontSize, 14);
      expect(center.activeFontSize, 18);
      expect(center.translationFontSize, 11);
      expect(center.activeTranslationFontSize, 12);
      expect(center.lineGap, 12);
      expect(center.mask, (0.22, 0.78));
      expect(center.fixedWindowLines, 3);
      expect(center.textAlign, TextAlign.center);
      expect(center.blockAnchor, Alignment.center);
      expect(center.activeLineScale, closeTo(1.04, 1e-9));
    });

    test('行槽高度按内容与行距推导', () {
      final left = resolveMusicLyricSpec(PortalMusicLayout.left, 1);
      // 在读行：44px 原文 + 16px 译文 + 6px 间距 = 82，加 18px 行距。
      expect(left.contentHeight(), closeTo(82, 1e-9));
      expect(left.slotHeight(), closeTo(100, 1e-9));

      final center = resolveMusicLyricSpec(PortalMusicLayout.center, 1);
      // 在读行：18px 原文 + 12px 译文 + 4px 间距 = 48，加 12px 行距。
      expect(center.contentHeight(), closeTo(48, 1e-9));
      expect(center.slotHeight(), closeTo(60, 1e-9));
    });
  });

  group('卡片边框、阴影与配色', () {
    test('两侧布局的内描边环与样式边框是两层且取值不同', () {
      for (var slot = 0; slot < 5; slot++) {
        final spec = resolveMusicDeckCard(PortalMusicLayout.left, slot);
        expect(spec.borderAlpha, kMusicIsometricBorderAlphas[slot]);
        expect(spec.ringAlpha, kMusicIsometricRingAlphas[slot]);
        // 样例两层的白透明度并不相同，否则就退化成一条边。
        expect(spec.borderAlpha, isNot(spec.ringAlpha));
      }
      expect(kMusicIsometricRingAlphas.first, 0.42);
      expect(kMusicIsometricRingAlphas.last, 0.14);

      final right = resolveMusicDeckCard(PortalMusicLayout.right, 0);
      expect(right.ringAlpha, 0.38);
      expect(right.borderAlpha, 0.4);
      expect(right.glowAlpha, kMusicSteppedGlowAlpha);
      expect(right.glowBlur, kMusicSteppedGlowBlur);
    });

    test('投影的位移/模糊/扩展半径按档位取自样例', () {
      final hero = resolveMusicDeckCard(PortalMusicLayout.left, 0);
      expect(hero.shadowOffset, const Offset(0, 32));
      expect(hero.shadowBlur, 70);
      expect(hero.shadowSpread, -10);
      expect(hero.glowAlpha, kMusicIsometricGlowAlpha);
      expect(hero.glowBlur, kMusicIsometricGlowBlur);

      final far = resolveMusicDeckCard(PortalMusicLayout.left, 4);
      expect(far.shadowOffset, const Offset(36, 32));
      expect(far.shadowBlur, 70);
      expect(far.shadowSpread, 0);
      expect(far.glowAlpha, 0);
    });

    test('封面的灰度后处理逐档压暗', () {
      expect([
        for (var slot = 0; slot < 5; slot++)
          resolveMusicDeckCard(PortalMusicLayout.left, slot).coverBrightness,
      ], kMusicIsometricCoverBrightness);
      expect(kMusicIsometricCoverBrightness.first, 1);
      expect(kMusicIsometricCoverBrightness.last, 0.55);

      for (var slot = 0; slot < 5; slot++) {
        final spec = resolveMusicDeckCard(PortalMusicLayout.left, slot);
        expect(spec.coverContrast, kMusicIsometricCoverContrast[slot]);
        expect(spec.overlayBottomAlpha, 0.95);
        expect(spec.overlayViaAlpha, kMusicIsometricOverlayViaAlphas[slot]);
        expect(spec.overlayTopAlpha, 0);
        expect(spec.overlayBlack, isFalse);
        expect(spec.surfaceAlpha, 1);
      }
    });

    test('居中布局为底部黑 + 顶部白高光的双向遮罩', () {
      for (var slot = -2; slot <= 2; slot++) {
        final index = slot + 2;
        final spec = resolveMusicDeckCard(PortalMusicLayout.center, slot);
        expect(spec.ringAlpha, kMusicCenterRingAlphas[index]);
        expect(spec.shadowOffset.dy, kMusicCenterShadowY[index]);
        expect(spec.shadowSpread, kMusicCenterShadowSpread[index]);
        expect(spec.surfaceAlpha, kMusicCenterSurfaceAlphas[index]);
        expect(spec.overlayBottomAlpha, kMusicCenterOverlayBottomAlphas[index]);
        expect(spec.overlayViaAlpha, 0);
        expect(spec.overlayTopAlpha, kMusicCenterOverlayTopAlphas[index]);
        expect(spec.overlayBlack, isTrue);
        // 居中卡组没有白色外发光，只在在读卡顶部有一条高光细线。
        expect(spec.glowAlpha, 0);
        expect(spec.sheenAlpha, slot == 0 ? 0.5 : 0);
      }
    });

    test('卡面圆角与描边宽度取自样例', () {
      expect(kMusicDeckCardRadius, 16);
      expect(kMusicDeckCardRadiusSmall, 12);
      expect(kMusicDeckCardBorderWidth, 1);
      for (var slot = 0; slot < 5; slot++) {
        expect(
          resolveMusicDeckCard(PortalMusicLayout.left, slot).radius,
          kMusicDeckCardRadius,
        );
      }
      expect(
        resolveMusicDeckCard(PortalMusicLayout.center, 0).radius,
        kMusicDeckCardRadius,
      );
      expect(
        resolveMusicDeckCard(PortalMusicLayout.center, 1).radius,
        kMusicDeckCardRadiusSmall,
      );
    });

    test('悬停态按样例逐档登记：居左整卡抬升，居右非在读卡上浮', () {
      for (var slot = 0; slot < 5; slot++) {
        final spec = resolveMusicDeckCard(PortalMusicLayout.left, slot);
        // 样例把每档的 data-hover-transform 写死，无统一公式。
        expect(spec.resolvedHoverOffset, kMusicIsometricHoverOffsets[slot]);
        expect(spec.resolvedHoverDepth, kMusicIsometricHoverDepths[slot]);
        expect(spec.resolvedHoverScale, kMusicIsometricHoverScales[slot]);
        expect(spec.resolvedHoverBorderAlpha, kMusicIsometricHoverBorderAlpha);
        // `.is-hovered` 会把 blur 归零。
        expect(spec.resolvedHoverBlur, 0);
        expect(spec.hoverBrightness, kMusicIsometricHoverBrightness);
      }

      // 居右非在读卡：样例 JS 悬停时追加 translateY(-14px) scale(1.02)。
      final right = resolveMusicDeckCard(PortalMusicLayout.right, 2);
      expect(right.resolvedHoverOffset, right.offset + kMusicSteppedHoverLift);
      expect(right.resolvedHoverDepth, right.depth);
      expect(
        right.resolvedHoverScale,
        closeTo(right.scale * kMusicSteppedHoverScale, 1e-9),
      );
      expect(right.resolvedHoverBorderAlpha, kMusicSteppedHoverBorderAlpha);
      expect(right.hoverCoverBrightness, kMusicDeckCardHoverCoverBrightness);
      // 两份样例的封面都是 group-hover:scale-105。
      expect(right.hoverCoverScale, kMusicDeckCardHoverCoverScale);

      // 居右在读卡：样例没有悬停变换与 hover:border 类，全部回落常态值。
      final rightHero = resolveMusicDeckCard(PortalMusicLayout.right, 0);
      expect(rightHero.resolvedHoverOffset, rightHero.offset);
      expect(rightHero.resolvedHoverScale, rightHero.scale);
      expect(rightHero.resolvedHoverBorderAlpha, rightHero.borderAlpha);
    });

    test('居中布局悬停态：外侧与内侧描边不同，在读卡无悬停描边', () {
      expect(
        resolveMusicDeckCard(
          PortalMusicLayout.center,
          -2,
        ).resolvedHoverBorderAlpha,
        0.40,
      );
      expect(
        resolveMusicDeckCard(
          PortalMusicLayout.center,
          -1,
        ).resolvedHoverBorderAlpha,
        0.50,
      );
      // 在读卡样例没有 hover:border 类，回落到常态值。
      final hero = resolveMusicDeckCard(PortalMusicLayout.center, 0);
      expect(hero.resolvedHoverBorderAlpha, hero.borderAlpha);
      // 在读卡不抽出：与两侧布局同一约定。
      expect(hero.resolvedHoverOffset, hero.offset);
      expect(hero.resolvedHoverScale, hero.scale);
      // 后排卡必须沿扇形外向抽出：只改描边与封面缩放不足以被察觉。
      final inner = resolveMusicDeckCard(PortalMusicLayout.center, 1);
      final outer = resolveMusicDeckCard(PortalMusicLayout.center, -2);
      expect(
        inner.resolvedHoverOffset.dx,
        closeTo(inner.offset.dx + 62.5, 1e-9),
      );
      expect(
        inner.resolvedHoverOffset.dy,
        closeTo(inner.offset.dy - kMusicCenterHoverLiftY, 1e-9),
      );
      expect(
        outer.resolvedHoverOffset.dx,
        closeTo(outer.offset.dx - 52.5, 1e-9),
      );
      expect(inner.resolvedHoverScale, greaterThan(inner.scale));
    });

    test('展开态放大后各档样式比例不变', () {
      final base = resolveMusicDeckCard(PortalMusicLayout.left, 2);
      final zoomed = base.zoomed(1.08);
      expect(zoomed.size, closeTo(base.size * 1.08, 1e-9));
      expect(zoomed.radius, closeTo(base.radius * 1.08, 1e-9));
      expect(zoomed.shadowBlur, closeTo(base.shadowBlur * 1.08, 1e-9));
      // 与尺寸无关的样式必须原样保留。
      expect(zoomed.opacity, base.opacity);
      expect(zoomed.borderAlpha, base.borderAlpha);
      expect(zoomed.ringAlpha, base.ringAlpha);
      expect(zoomed.coverBrightness, base.coverBrightness);
      expect(zoomed.coverContrast, base.coverContrast);
      expect(zoomed.overlayViaAlpha, base.overlayViaAlpha);
    });
  });

  group('卡面装饰层级', () {
    test('两侧布局在读卡是徽章 + 均衡器 + 信息带', () {
      final hero = resolveMusicDeckCardChrome(
        PortalMusicLayout.left,
        active: true,
        slot: 0,
      );
      expect(hero.heroBadge, isTrue);
      expect(hero.equalizer, isTrue);
      expect(hero.indexTag, isFalse);
      expect(hero.metaBand, isTrue);
      expect(hero.counterChip, isFalse);
      expect(hero.padding, kMusicDeckCardSidePadding);
    });

    test('两侧布局非在读卡是序号胶囊 + 信息带', () {
      final stacked = resolveMusicDeckCardChrome(
        PortalMusicLayout.right,
        active: false,
        slot: 2,
      );
      expect(stacked.heroBadge, isFalse);
      expect(stacked.equalizer, isFalse);
      expect(stacked.indexTag, isTrue);
      expect(stacked.metaBand, isTrue);
      expect(stacked.counterChip, isFalse);
    });

    test('居中布局只在角落标序号，在读卡另有规格胶囊', () {
      final hero = resolveMusicDeckCardChrome(
        PortalMusicLayout.center,
        active: true,
        slot: 0,
      );
      expect(hero.counterChip, isTrue);
      expect(hero.counterAlignment, Alignment.topLeft);
      expect(hero.metaBand, isFalse);
      expect(hero.heroBadge, isFalse);
      // 在读卡右上角是样例的「DSD256」规格胶囊。
      expect(hero.formatTag, isTrue);
      expect(hero.padding, kMusicDeckCardCenterPadding);

      // 非在读卡没有规格胶囊。
      for (final slot in <int>[-2, -1, 1, 2]) {
        expect(
          resolveMusicDeckCardChrome(
            PortalMusicLayout.center,
            active: false,
            slot: slot,
          ).formatTag,
          isFalse,
        );
      }

      // 样例：左半与在读卡贴左上，右半贴右上。
      for (final slot in <int>[-2, -1, 0]) {
        expect(
          resolveMusicDeckCardChrome(
            PortalMusicLayout.center,
            active: false,
            slot: slot,
          ).counterAlignment,
          Alignment.topLeft,
        );
      }
      for (final slot in <int>[1, 2]) {
        expect(
          resolveMusicDeckCardChrome(
            PortalMusicLayout.center,
            active: false,
            slot: slot,
          ).counterAlignment,
          Alignment.topRight,
        );
      }
    });
  });

  group('歌词配色与不透明度档位', () {
    test('字重与在读行外发光取自样例', () {
      final left = resolveMusicLyricSpec(PortalMusicLayout.left, 1);
      expect(left.fontWeight, FontWeight.w300);
      expect(left.translationFontWeight, FontWeight.w300);
      expect(left.activeFontWeight, FontWeight.w500);
      expect(left.activeTranslationFontWeight, FontWeight.w300);
      expect(left.activeLineGlowAlpha, kMusicSideLyricGlowAlpha);
      expect(left.activeLineGlowBlur, kMusicSideLyricGlowBlur);

      // 居中布局非在读行是 font-normal，与两侧的 font-light 不同。
      final center = resolveMusicLyricSpec(PortalMusicLayout.center, 1);
      expect(center.fontWeight, FontWeight.w400);
      expect(center.translationFontWeight, FontWeight.w400);
      expect(center.activeTranslationFontWeight, FontWeight.w400);
      expect(center.activeLineGlowAlpha, kMusicCenterLyricGlowAlpha);
      expect(center.activeLineGlowBlur, kMusicCenterLyricGlowBlur);
    });

    test('原文与译文是两级色，在读行另有读色', () {
      expect(kMusicLyricTextColor, const Color(0xFFE2E2E6));
      expect(kMusicLyricTranslationColor, const Color(0xFFC4C7CA));
      expect(kMusicLyricActiveTextColor, const Color(0xFFFFFFFF));

      final left = resolveMusicLyricSpec(PortalMusicLayout.left, 1);
      expect(left.textColor, kMusicLyricTextColor);
      expect(left.translationColor, kMusicLyricTranslationColor);
      expect(left.activeTextColor, kMusicLyricActiveTextColor);
      expect(
        left.activeTranslationColor,
        kMusicLyricSideActiveTranslationColor,
      );

      // 居中的在读译文仍用普通译文色。
      final center = resolveMusicLyricSpec(PortalMusicLayout.center, 1);
      expect(center.activeTranslationColor, kMusicLyricTranslationColor);
    });

    test('在读行底衬只有两侧布局有，左侧强调条已整体移除', () {
      for (final layout in <PortalMusicLayout>[
        PortalMusicLayout.left,
        PortalMusicLayout.right,
      ]) {
        final spec = resolveMusicLyricSpec(layout, 1);
        expect(spec.activeLineBackgroundColor, const Color(0x660C0E11));
        expect(spec.activeLineRadius, 12);
      }
      final center = resolveMusicLyricSpec(PortalMusicLayout.center, 1);
      expect(center.activeLineBackgroundColor, isNull);
    });

    test('在读行纵向内边距与样例 py-3.5 / py-3 / 无 一致', () {
      expect(
        resolveMusicLyricSpec(PortalMusicLayout.left, 1).activeLinePaddingY,
        14,
      );
      expect(
        resolveMusicLyricSpec(PortalMusicLayout.right, 1).activeLinePaddingY,
        12,
      );
      expect(
        resolveMusicLyricSpec(PortalMusicLayout.center, 1).activeLinePaddingY,
        0,
      );
      expect(
        resolveMusicLyricSpec(PortalMusicLayout.left, 1).activeLinePaddingX,
        16,
      );
    });

    test('非在读行按距离取不透明度档位', () {
      final left = resolveMusicLyricSpec(PortalMusicLayout.left, 1);
      expect(musicLyricLineOpacity(left, 0), 1);
      expect(musicLyricLineOpacity(left, -1), 0.40);
      expect(musicLyricLineOpacity(left, -2), 0.20);
      // 超出档位表时取最远端。
      expect(musicLyricLineOpacity(left, -5), 0.20);
      expect(musicLyricLineOpacity(left, 1), 0.50);
      expect(musicLyricLineOpacity(left, 2), 0.30);
      expect(musicLyricLineOpacity(left, 3), 0.15);
      expect(musicLyricLineOpacity(left, 9), 0.15);

      final center = resolveMusicLyricSpec(PortalMusicLayout.center, 1);
      expect(musicLyricLineOpacity(center, 0), 1);
      expect(musicLyricLineOpacity(center, -1), 0.25);
      expect(musicLyricLineOpacity(center, 1), 0.30);
      expect(musicLyricLineOpacity(center, 2), 0.15);
    });

    test('字号按 px 设定，译文等派生尺寸同比缩放', () {
      // 未显式设定时等于该布局的样例基准字号（两侧 44/18，居中 18/14）。
      expect(
        resolveMusicLyricSpec(PortalMusicLayout.left, 1).activeFontSize,
        44,
      );
      expect(resolveMusicLyricSpec(PortalMusicLayout.left, 1).fontSize, 18);
      expect(
        resolveMusicLyricSpec(PortalMusicLayout.center, 1).activeFontSize,
        18,
      );

      final resized = resolveMusicLyricSpec(
        PortalMusicLayout.left,
        1,
        activeFontSizePx: 22,
        inactiveFontSizePx: 9,
      );
      expect(resized.activeFontSize, 22);
      expect(resized.fontSize, 9);
      // 比值 22/44 = 0.5 与 9/18 = 0.5：译文按同比值缩放。
      expect(resized.activeTranslationFontSize, 8);
      expect(resized.translationFontSize, 6);
      // 设备缩放系数仍然生效。
      expect(
        resolveMusicLyricSpec(
          PortalMusicLayout.left,
          0.5,
          activeFontSizePx: 22,
        ).activeFontSize,
        11,
      );
    });

    test('非当前句透明度缩放样例阶梯且不影响到读行', () {
      // 设置值等于默认值时倍率为 1，阶梯与样例一致。
      final sample = resolveMusicLyricSpec(
        PortalMusicLayout.left,
        1,
        inactiveOpacity: kMusicLyricLadderOpacityAnchor,
      );
      expect(musicLyricLineOpacity(sample, 1), 0.50);
      expect(musicLyricLineOpacity(sample, 3), 0.15);

      // 默认值 0.8 → 倍率 1.6：未读行整体提亮，超过满亮的档位被夹到 1。
      final fresh = resolveMusicLyricSpec(
        PortalMusicLayout.left,
        1,
        inactiveOpacity: PortalLyricVisualSettings.defaults.inactiveOpacity,
      );
      expect(musicLyricLineOpacity(fresh, 1), 0.80);
      expect(musicLyricLineOpacity(fresh, 2), 0.48);
      expect(musicLyricLineOpacity(fresh, 3), 0.24);

      // 倍率 1.0 / 0.5 = 2：整体提亮，最远档 0.15 → 0.30，最近档封顶满亮。
      final bright = resolveMusicLyricSpec(
        PortalMusicLayout.left,
        1,
        inactiveOpacity: 1,
      );
      expect(musicLyricLineOpacity(bright, 0), 1);
      expect(musicLyricLineOpacity(bright, 1), 1);
      expect(musicLyricLineOpacity(bright, 3), 0.30);

      // 倍率 0.25 / 0.5 = 0.5：整体压暗，在读行始终满亮。
      final dim = resolveMusicLyricSpec(
        PortalMusicLayout.left,
        1,
        inactiveOpacity: 0.25,
      );
      expect(musicLyricLineOpacity(dim, 0), 1);
      expect(musicLyricLineOpacity(dim, 1), 0.25);
      expect(musicLyricLineOpacity(dim, 2), 0.15);
    });

    test('译文的额外压暗只在样例标注的地方生效', () {
      final left = resolveMusicLyricSpec(PortalMusicLayout.left, 1);
      // 两侧只把最靠前一行压到 /70，其余不加压暗。
      expect(left.translationAlpha(-1), 1);
      expect(left.translationAlpha(-2), kMusicLyricFarTranslationAlpha);
      expect(left.translationAlpha(1), 1);

      // 居中把每一条非在读译文统一压到 /60。
      final center = resolveMusicLyricSpec(PortalMusicLayout.center, 1);
      expect(center.translationAlpha(-1), kMusicCenterLyricTranslationAlpha);
      expect(center.translationAlpha(1), kMusicCenterLyricTranslationAlpha);
    });
  });

  group('底部播放胶囊与音频参数胶囊', () {
    test('底部胶囊的水平上限只有右侧布局不同', () {
      expect(musicFooterMaxWidth(PortalMusicLayout.left), 1024);
      expect(musicFooterMaxWidth(PortalMusicLayout.center), 1024);
      // 样例 Right Layout:372 是 max-w-6xl，与 Left/Center 的 max-w-5xl 不同。
      expect(musicFooterMaxWidth(PortalMusicLayout.right), 1152);
      expect(kMusicFooterBottomMargin, 8);
      expect(kMusicFooterHeight, 86);
    });

    test('音频参数胶囊的高度与两行行盒同源', () {
      // 内边距 16 + 标题行 14 + 规格行 16 = 46；两行文本用强制 strut 按同一组
      // 行高排布，胶囊高度若与行盒不同源就会差出亚像素并溢出。
      expect(kMusicDeckSpecPadding * 2 + 14 + 16, kMusicDeckSpecHeight);
      expect(kMusicDeckSpecBackgroundAlpha, 0.6);
      expect(kMusicDeckSpecBorderAlpha, 0.15);
      // 样例的卡组列纵向居中「舞台 + 间距 + 胶囊」整组，不只是舞台。
      expect(
        musicDeckStackHeight(PortalMusicLayout.left, 385),
        closeTo(385 + 8 + 46, 1e-9),
      );
      expect(
        musicDeckStackHeight(PortalMusicLayout.right, 390),
        closeTo(390 + 12 + 46, 1e-9),
      );
    });

    test('卡组舞台纵向居中会扣掉尾部元素的高度', () {
      final frame = MusicSideLayoutFrame.resolve(_reference);
      final bare = MusicDeckStageGeometry.resolveSide(
        layout: PortalMusicLayout.left,
        sectionRect: frame.deckSection(PortalMusicLayout.left),
        scale: frame.scale,
      );
      final withTrailing = MusicDeckStageGeometry.resolveSide(
        layout: PortalMusicLayout.left,
        sectionRect: frame.deckSection(PortalMusicLayout.left),
        scale: frame.scale,
        trailingHeight: 53,
      );
      // 整组居中时舞台上移尾部高度的一半。
      expect(bare.rect.top - withTrailing.rect.top, closeTo(53 / 2, 1e-9));
      expect(withTrailing.rect.height, bare.rect.height);
    });
  });

  group('顶栏块高度', () {
    test('两行文字块永远不超过顶栏块高度', () {
      // 覆盖超小窗口到超宽窗口，顶栏块必须始终容得下两行文字。
      const sizes = <double>[
        0.2,
        0.35,
        0.5,
        0.66,
        0.8,
        0.85,
        0.9,
        1,
        1.2,
        1.6,
        2.4,
      ];
      for (final scale in sizes) {
        expect(
          musicHeaderBlockHeight(scale),
          greaterThanOrEqualTo(musicHeaderContentHeight(scale) - 1e-9),
          reason: '缩放 $scale 下顶栏块容不下文字',
        );
      }
    });

    test('字号带上限下限，顶栏块不低于物理下限', () {
      expect(musicHeaderTitleSize(0.1), 23);
      expect(musicHeaderTitleSize(1), 27);
      expect(musicHeaderTitleSize(4), 34);
      expect(musicHeaderSubtitleSize(0.1), 14);
      expect(musicHeaderSubtitleSize(1), 16);
      expect(musicHeaderSubtitleSize(4), 19);

      expect(musicHeaderBlockHeight(0.05), kMusicLayoutHeaderBlockMinHeight);
      // 基准尺寸下两行文字（55.26）小于样例顶栏块（56），取样例值。
      expect(musicHeaderBlockHeight(1), kMusicLayoutHeaderBlockHeight);
    });
  });
}
