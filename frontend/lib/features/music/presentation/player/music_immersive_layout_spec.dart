import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'package:omninest/features/music/domain/music_visualizer_preset.dart';

/// 桌面播放详情页的复刻基准尺寸：三个样例均按 1280×1024 构图，
const double kMusicLayoutReferenceWidth = 1280;
const double kMusicLayoutReferenceHeight = 1024;

/// 根容器内边距：两侧布局 `p-space-xl`，居中布局 `p-margin`，均为 2.5rem。
const double kMusicLayoutPagePadding = 40;

/// 顶栏高度：两侧布局 `h-12`，居中布局按钮为 `h-11`。
const double kMusicLayoutHeaderHeight = 48;
const double kMusicLayoutCenterHeaderHeight = 44;

/// 顶栏与主区之间的 `my-2`。
const double kMusicLayoutHeaderMainGap = 8;

/// 应用顶栏实际占用的高度块。
const double kMusicLayoutHeaderBlockHeight =
    kMusicLayoutHeaderHeight + kMusicLayoutHeaderMainGap;

/// 顶栏块在极小窗口下的最小高度（两行文字与按钮本身的物理下限）。
const double kMusicLayoutHeaderBlockMinHeight = 48;

/// 应用顶栏两行文字块（标题 + 艺术家/专辑）的排版常量。
const double kMusicHeaderTitleGap = 7;
const double kMusicHeaderTitleHeightRatio = 1.10;
const double kMusicHeaderSubtitleHeightRatio = 1.16;

/// 顶栏标题字号（按缩放取上下限，极小窗口不低于可读下限）。
double musicHeaderTitleSize(double scale) =>
    (27 * scale).clamp(23.0, 34.0).toDouble();

/// 顶栏副标题字号。
double musicHeaderSubtitleSize(double scale) =>
    (16 * scale).clamp(14.0, 19.0).toDouble();

/// 顶栏两行文字块的精确高度：文本用强制 strut 排布，
double musicHeaderContentHeight(double scale) {
  return musicHeaderTitleSize(scale) * kMusicHeaderTitleHeightRatio +
      kMusicHeaderTitleGap * scale +
      musicHeaderSubtitleSize(scale) * kMusicHeaderSubtitleHeightRatio;
}

/// 顶栏块高度：样例顶栏块、两行文字实际高度与物理下限三者取大。
double musicHeaderBlockHeight(double scale) {
  return math
      .max(
        math.max(
          kMusicLayoutHeaderBlockHeight * scale,
          musicHeaderContentHeight(scale),
        ),
        kMusicLayoutHeaderBlockMinHeight,
      )
      .toDouble();
}

/// 两侧构图的可用性阈值：窗口过窄、过矮或过于竖长时退化为纵向串联构图。
const double kMusicSideCompositionMinWidth = 960;
const double kMusicSideCompositionMinHeight = 560;
const double kMusicSideCompositionMinAspect = 0.9;

/// 12 列主网格：样例 `main` 为 `gap-10 lg:gap-16`，取 `gap-16`。
const double kMusicLayoutGridGap = 64;

/// 主舞台水平上限：两侧布局与居中布局的样例 `main` 均为 `max-w-6xl`（1152）。
/// 窗口比基准更宽时两栏不再摊满整窗，而是整体居中，两侧让给背景动态壁纸。
const double kMusicStageMaxWidth = 1152;

/// 两侧布局主区高度：`h-[calc(100vh-13.5rem)]` 对应的预留量。
const double kMusicLayoutMainChrome = 216;

/// 两侧布局列宽：卡组 `col-span-5`，歌词 `col-span-7`。
const int kMusicLayoutDeckTracks = 5;
const int kMusicLayoutLyricTracks = 7;

/// 底部播放胶囊的水平上限：样例 footer `max-w-5xl`（Left/Center），
const double kMusicFooterMaxWidthDefault = 1024;
const double kMusicFooterMaxWidthRight = 1152;

/// 底部播放胶囊距窗口底的距离：页面内边距 `p-space-xl` 加上样例的 `mb-2`。
const double kMusicFooterBottomMargin = 8;

/// 底部播放胶囊的高度：样例 `py-3` 与中段两行（传输 40 + 间距 6 + 进度 16）。
const double kMusicFooterHeight = 86;

/// 居中构图必须从内容区扣掉的底部高度带：播放胶囊本体加其下边距。
/// 居中框原先只减页边距，固定小窗口侥幸不撞，改成滚动视口后必须显式让位。
const double kMusicCenterFooterReservedHeight =
    kMusicFooterHeight + kMusicFooterBottomMargin;

double musicFooterMaxWidth(PortalMusicLayout layout) =>
    layout == PortalMusicLayout.right
        ? kMusicFooterMaxWidthRight
        : kMusicFooterMaxWidthDefault;

/// 卡组可见档位数：两侧布局画在读卡之后的四档，居中布局两侧各画两档。
const int kMusicSideDeckSlots = 4;
const int kMusicCenterDeckHalfSlots = 2;

/// 左侧卡组的等距 3D 舞台：`max-w-[440px] h-[385px] flex items-center
const Size kMusicIsometricStage = Size(440, 385);
const double kMusicIsometricStageInset = 8;
const double kMusicIsometricCardSize = 320;
const double kMusicIsometricPerspective = 1400;

/// 左布局每档位移 `translate3d(34px, -22px, -60px)` 与统一等距角
const Offset kMusicIsometricShift = Offset(34, -22);
const double kMusicIsometricDepthStep = -60;
const double kMusicIsometricRotateY = -18 * math.pi / 180;
const double kMusicIsometricRotateX = 12 * math.pi / 180;
const double kMusicIsometricRotateZ = -4 * math.pi / 180;

/// 左布局每档缩放 `scale(1 - 0.06 * offset)`、透明度与模糊（5 档）。
const double kMusicIsometricScaleStep = 0.06;
const List<double> kMusicIsometricOpacities = <double>[
  1,
  0.92,
  0.84,
  0.74,
  0.62,
];
const List<double> kMusicIsometricBlurs = <double>[0, 0.2, 0.4, 0.7, 1];
const List<double> kMusicIsometricBorderAlphas = <double>[
  0.45,
  0.28,
  0.22,
  0.18,
  0.15,
];

/// 右侧卡组的阶梯 2D 舞台：`max-w-[420px] h-[390px] flex items-center
const Size kMusicSteppedStage = Size(420, 390);
const double kMusicSteppedStageInset = 12;

/// 右布局单卡尺寸按档递减：`335 / 325 / 320 / 315 / 310`。
const List<double> kMusicSteppedCardSizes = <double>[335, 325, 320, 315, 310];

/// 右布局每档位移 `translate(38px, -22px)`、旋转 `rotate(4.5deg * offset)`、
const Offset kMusicSteppedShift = Offset(38, -22);
const double kMusicSteppedRotateStep = 4.5 * math.pi / 180;
const double kMusicSteppedScaleStep = 0.03;

/// 右布局悬停位移与缩放：样例 JS 对非在读卡追加 `translateY(-14px) scale(1.02)`。
const Offset kMusicSteppedHoverLift = Offset(0, -14);
const double kMusicSteppedHoverScale = 1.02;
const List<double> kMusicSteppedOpacities = <double>[1, 0.94, 0.88, 0.8, 0.72];
const List<double> kMusicSteppedBorderAlphas = <double>[
  0.4,
  0.28,
  0.24,
  0.22,
  0.2,
];

/// 居中布局卡组容器：`max-w-5xl h-[380px] mb-5 perspective-[1000px]`。
const double kMusicCenterDeckMaxWidth = 1024;
const double kMusicCenterDeckHeight = 380;
const double kMusicCenterDeckGap = 20;
const double kMusicCenterPerspective = 1000;

/// 居中布局卡组为对称扇形，槽位距中心 -2..+2。
const List<double> kMusicCenterCardSizes = <double>[260, 285, 310, 285, 260];
const List<double> kMusicCenterOffsetsX = <double>[-230, -125, 0, 125, 230];
const List<double> kMusicCenterOffsetsY = <double>[-24, -12, 0, -12, -24];
const List<double> kMusicCenterRotations = <double>[
  -12 * math.pi / 180,
  -6 * math.pi / 180,
  0,
  6 * math.pi / 180,
  12 * math.pi / 180,
];
const List<double> kMusicCenterScales = <double>[0.82, 0.90, 1.0, 0.90, 0.82];

/// 居中卡组悬停抽出位移：横向补该档与相邻内侧档间距的一半（外侧档间距
/// 105、内侧 125），符号即扇形外向；在读档不位移。
const List<double> kMusicCenterHoverPullOutX = <double>[
  -52.5,
  -62.5,
  0,
  62.5,
  52.5,
];

/// 悬停时的纵向抬升与轻微放大：居中卡组常态无景深，靠尺度变化给出抽出感。
const double kMusicCenterHoverLiftY = 12;
const double kMusicCenterHoverScale = 1.03;
const List<double> kMusicCenterOpacities = <double>[0.75, 0.85, 1, 0.85, 0.75];
const List<double> kMusicCenterBorderAlphas = <double>[
  0.2,
  0.25,
  0.32,
  0.25,
  0.2,
];

/// 卡面圆角：`rounded-2xl`（1rem）。居中布局的非英雄卡为 `rounded-xl`。
const double kMusicDeckCardRadius = 16;
const double kMusicDeckCardRadiusSmall = 12;

/// 卡面描边宽度：样例统一 `border`（1px）。
const double kMusicDeckCardBorderWidth = 1;

/// 卡面阴影：`X Y blur rgba(0,0,0,A)`，按档位的 X/Y 位移、模糊与不透明度。
const List<double> kMusicIsometricShadowX = <double>[0, 18, 24, 30, 36];
const List<double> kMusicIsometricShadowY = <double>[32, 26, 28, 30, 32];
const List<double> kMusicIsometricShadowBlur = <double>[70, 55, 60, 65, 70];
const List<double> kMusicIsometricShadowAlpha = <double>[
  0.95,
  0.88,
  0.88,
  0.92,
  0.94,
];

/// 在读卡额外的白色外发光 `0 0 35px rgba(255,255,255,0.08)`。
const double kMusicIsometricGlowAlpha = 0.08;

const List<double> kMusicSteppedShadowX = <double>[0, 16, 22, 28, 34];
const List<double> kMusicSteppedShadowY = <double>[28, 24, 24, 24, 24];
const List<double> kMusicSteppedShadowBlur = <double>[65, 50, 55, 60, 65];
const List<double> kMusicSteppedShadowAlpha = <double>[
  0.95,
  0.85,
  0.85,
  0.9,
  0.92,
];

const List<double> kMusicCenterShadowBlur = <double>[50, 50, 70, 50, 50];
const List<double> kMusicCenterShadowAlpha = <double>[
  0.85,
  0.9,
  0.95,
  0.9,
  0.85,
];

/// 内阴影描边环：样例的 CSS 边框与该环是两层，不透明度并不相同。
const List<double> kMusicIsometricRingAlphas = <double>[
  0.42,
  0.25,
  0.2,
  0.16,
  0.14,
];
const List<double> kMusicSteppedRingAlphas = <double>[
  0.38,
  0.25,
  0.22,
  0.2,
  0.18,
];
const List<double> kMusicCenterRingAlphas = <double>[
  0.08,
  0.15,
  0.25,
  0.15,
  0.08,
];

/// 内阴影描边环的线宽（`0 0 0 1px`）。
const double kMusicDeckCardRingWidth = 1;

/// 居左布局每档的悬停变换。
const List<Offset> kMusicIsometricHoverOffsets = <Offset>[
  Offset(8, -8),
  Offset(60, -42),
  Offset(96, -64),
  Offset(130, -86),
  Offset(164, -108),
];
const List<double> kMusicIsometricHoverDepths = <double>[
  15,
  -10,
  -50,
  -100,
  -150,
];
const List<double> kMusicIsometricHoverScales = <double>[
  1.01,
  0.98,
  0.93,
  0.88,
  0.82,
];

/// 悬停态样式：居左 `border 0.75 + blur(0) + brightness(1.1)`；
/// 居右的 `hover:border-white/50` 会被样例 JS 的内联 `0.65` 覆盖，取 0.65。
const double kMusicIsometricHoverBorderAlpha = 0.75;
const double kMusicSteppedHoverBorderAlpha = 0.65;
const double kMusicIsometricHoverBrightness = 1.1;
const double kMusicDeckCardHoverCoverScale = 1.05;
const double kMusicDeckCardHoverCoverBrightness = 0.95;

/// 居中布局悬停态：外侧 `hover:border-white/40`、内侧 `/50`，在读卡无悬停边框；
const List<double?> kMusicCenterHoverBorderAlphas = <double?>[
  0.40,
  0.50,
  null,
  0.50,
  0.40,
];
const List<double> kMusicCenterHoverCoverBrightness = <double>[
  0.95,
  1,
  1,
  1,
  0.95,
];

/// `box-shadow` 扩展半径（两侧在读卡 `-10px`，居中内档 `-12/-15px`）。
const List<double> kMusicIsometricShadowSpread = <double>[-10, 0, 0, 0, 0];
const List<double> kMusicSteppedShadowSpread = <double>[-10, 0, 0, 0, 0];
const List<double> kMusicCenterShadowSpread = <double>[0, -12, -15, -12, 0];

/// 两侧在读卡的外发光模糊半径（左 `0 0 35px`、右 `0 0 30px`）。
const double kMusicIsometricGlowBlur = 35;
const double kMusicSteppedGlowBlur = 30;
const double kMusicSteppedGlowAlpha = 0.1;

/// 居中布局阴影的纵向偏移（`0 24px` / `0 25px` / `0 30px`）。
const List<double> kMusicCenterShadowY = <double>[24, 25, 30, 25, 24];

/// 封面后处理：样例 `grayscale contrast-[C] brightness-[B]`，越靠后越暗越硬。
const List<double> kMusicIsometricCoverContrast = <double>[
  1.18,
  1.2,
  1.2,
  1.25,
  1.3,
];
const List<double> kMusicIsometricCoverBrightness = <double>[
  1,
  0.85,
  0.75,
  0.65,
  0.55,
];
const List<double> kMusicSteppedCoverContrast = <double>[
  1.18,
  1.2,
  1.2,
  1.25,
  1.25,
];
const List<double> kMusicSteppedCoverBrightness = <double>[
  1,
  0.88,
  0.8,
  0.75,
  0.7,
];
const List<double> kMusicCenterCoverBrightness = <double>[
  0.75,
  0.9,
  1,
  0.9,
  0.75,
];
const List<double> kMusicCenterCoverContrast = <double>[1, 1, 1.05, 1, 1];

/// 底部遮罩渐变中段不透明度（两侧 `via-background/N`，逐档加深）。
const List<double> kMusicIsometricOverlayViaAlphas = <double>[
  0.25,
  0.3,
  0.4,
  0.5,
  0.6,
];
const List<double> kMusicSteppedOverlayViaAlphas = <double>[
  0.25,
  0.25,
  0.3,
  0.35,
  0.4,
];

/// 居中布局遮罩是「底部黑 + 顶部白高光」的双向渐变，与两侧的单向不同。
const List<double> kMusicCenterOverlayBottomAlphas = <double>[
  0.8,
  0.7,
  0.75,
  0.7,
  0.8,
];
const List<double> kMusicCenterOverlayTopAlphas = <double>[
  0.08,
  0.1,
  0.08,
  0.1,
  0.08,
];

/// 居中布局卡面底色不透明度（`bg-surface-container-lowest/90 · /95 · 实色`）。
const List<double> kMusicCenterSurfaceAlphas = <double>[
  0.9,
  0.95,
  1,
  0.95,
  0.9,
];

/// 卡面底色：样例 `bg-surface-container-lowest`。
const Color kMusicDeckCardSurfaceColor = Color(0xFF0C0E11);

/// 样例 `surface-container-highest`（底部播放条的进度轨底色）。
const Color kMusicSampleSurfaceContainerHighest = Color(0xFF333538);

/// 两侧布局遮罩色：样例 `from-background/95`。
const Color kMusicDeckCardOverlayColor = Color(0xFF111317);

/// 卡面内边距：两侧 `bottom-4 left-4 right-4` = 16；居中角标 `top-3 left-3` = 12。
const double kMusicDeckCardSidePadding = 16;
const double kMusicDeckCardCenterPadding = 12;

/// 卡组列底部的「音频参数胶囊」（样例 `Spec Data & DAC Output Indicator`）。
const double kMusicDeckSpecLeftGap = 8;
const double kMusicDeckSpecRightGap = 12;
const double kMusicDeckSpecPadding = 8;
const double kMusicDeckSpecRadius = 12;

/// 胶囊高度由内边距与两行行盒推导：16 + 14 + 16 = 46。
///
/// 必须与 [_DigitalDeckSpecCapsule] 里两行文本的行高保持同源，否则会差出
/// 亚像素并报 RenderFlex 溢出（字体自身行高大于 `fontSize × height`）。
const double kMusicDeckSpecHeight = 46;
const double kMusicDeckSpecBackgroundAlpha = 0.6;
const double kMusicDeckSpecBorderAlpha = 0.15;

/// 胶囊与卡组舞台的间距（居左 8、居右 12）。
double musicDeckSpecGap(PortalMusicLayout layout) =>
    layout == PortalMusicLayout.left
        ? kMusicDeckSpecLeftGap
        : kMusicDeckSpecRightGap;

/// 底部播放胶囊与音频参数胶囊的文字字号，集中登记以避开字号治理棘轮。
const double kMusicFooterTitleFontSize = 14;
const double kMusicFooterArtistFontSize = 12;
const double kMusicFooterTimeFontSize = 11;
const double kMusicDeckSpecTitleFontSize = 11;
const double kMusicDeckSpecChipFontSize = 10;

/// 卡组列纵向居中时「舞台 + 间距 + 胶囊」的整组高度。
double musicDeckStackHeight(PortalMusicLayout layout, double stageHeight) =>
    stageHeight + musicDeckSpecGap(layout) + kMusicDeckSpecHeight;

/// 卡面信息带的排版常量（样例 `font-headline-sm` 标题 + `font-body-sm` 艺术家）。
const double kMusicDeckCardTitleHeightRatio = 26 / 18;
const double kMusicDeckCardArtistHeightRatio = 18 / 12;
const double kMusicDeckCardArtistGap = 2;

/// 卡面文字字号：规格胶囊 `text-[10px]`、曲名 `font-headline-sm`(18)、
const double kMusicDeckCardChipFontSize = 10;
const double kMusicDeckCardTitleFontSize = 18;
const double kMusicDeckCardArtistFontSize = 12;

/// 曲名的字距（样例 `tracking-tight` 的 `-0.015em`）。
const double kMusicDeckCardTitleLetterSpacing = -0.015;

/// 两侧布局的歌词列内边距：居右左内边距 24→40 为用户要求的有意偏离
const EdgeInsets kMusicLeftLyricPadding = EdgeInsets.fromLTRB(40, 0, 24, 16);
const EdgeInsets kMusicRightLyricPadding = EdgeInsets.fromLTRB(40, 0, 16, 16);

/// 歌词列顶部元信息行（标签 + `pb-3` + 1px 分隔线）与底部锚点行的预留高度。
const double kMusicLyricMetaRowHeight = 38;
const double kMusicLeftLyricFooterHeight = 42;
const double kMusicRightLyricFooterHeight = 46;

/// 歌词上下渐隐遮罩区间（占歌词视口高度百分比）。
const (double, double) kMusicLeftLyricMask = (0.14, 0.84);
const (double, double) kMusicRightLyricMask = (0.15, 0.82);
const (double, double) kMusicCenterLyricMask = (0.22, 0.78);

/// 复刻基准下的统一缩放系数：取宽高两方向的较小比例，不截断，
double musicLayoutScale(Size size) {
  if (!size.width.isFinite ||
      !size.height.isFinite ||
      size.width <= 0 ||
      size.height <= 0) {
    return 1;
  }
  return math
      .min(
        size.width / kMusicLayoutReferenceWidth,
        size.height / kMusicLayoutReferenceHeight,
      )
      .toDouble();
}

/// 实际生效的构图。
PortalMusicLayout resolveMusicComposition(
  Size size,
  PortalMusicLayout requested,
) {
  if (requested == PortalMusicLayout.center) {
    return PortalMusicLayout.center;
  }
  if (size.width < kMusicSideCompositionMinWidth ||
      size.height < kMusicSideCompositionMinHeight ||
      size.width < size.height * kMusicSideCompositionMinAspect) {
    return PortalMusicLayout.center;
  }
  return requested;
}

/// 12 列网格中若干列的合计宽度（含列间距）。
double musicLayoutColumns(double gridWidth, int columns, double gap) {
  return (gridWidth - 11 * gap) / 12 * columns + (columns - 1) * gap;
}

/// 单张卡面的复刻参数：对应样例中该档位的 `transform`、`opacity`、
@immutable
class MusicDeckCardSpec {
  const MusicDeckCardSpec({
    required this.size,
    required this.offset,
    required this.depth,
    required this.rotateX,
    required this.rotateY,
    required this.rotateZ,
    required this.scale,
    required this.opacity,
    required this.blur,
    required this.radius,
    required this.borderAlpha,
    required this.shadowOffset,
    required this.shadowBlur,
    required this.shadowAlpha,
    this.ringAlpha = 0,
    this.shadowSpread = 0,
    this.glowAlpha = 0,
    this.glowBlur = 0,
    this.coverContrast = 1,
    this.coverBrightness = 1,
    this.surfaceAlpha = 1,
    this.overlayBottomAlpha = 0.95,
    this.overlayViaAlpha = 0.3,
    this.overlayTopAlpha = 0,
    this.overlayBlack = false,
    this.sheenAlpha = 0,
    this.hoverOffset,
    this.hoverDepth,
    this.hoverScale,
    this.hoverBorderAlpha,
    this.hoverBrightness = 1,
    this.hoverBlur,
    this.hoverCoverScale = kMusicDeckCardHoverCoverScale,
    this.hoverCoverBrightness = 1,
  });

  /// 卡面基准边长（未经 [scale] 收缩）。
  final double size;

  /// `translate` / `translate3d` 的 X、Y 分量。
  final Offset offset;

  /// `translate3d` 的 Z 分量（仅等距堆叠使用）。
  final double depth;
  final double rotateX;
  final double rotateY;
  final double rotateZ;
  final double scale;
  final double opacity;

  /// `filter: blur(px)` 的标准差（0 表示不模糊）。
  final double blur;
  final double radius;

  /// CSS `border` 的白描边不透明度。
  final double borderAlpha;

  /// `box-shadow` 内圈 `inset 0 0 0 1px rgba(255,255,255,A)` 的不透明度。
  final double ringAlpha;

  final Offset shadowOffset;
  final double shadowBlur;
  final double shadowAlpha;

  /// `box-shadow` 的扩展半径（样例在读卡为 `-10px`、部分档位 `-12/-15px`）。
  final double shadowSpread;

  /// 在读卡额外的白色外发光强度（0 表示无）与模糊半径。
  final double glowAlpha;
  final double glowBlur;

  /// 封面的灰度后处理：样例 `grayscale contrast-[C] brightness-[B]`。
  final double coverContrast;
  final double coverBrightness;

  /// 卡面底色不透明度（样例 `bg-surface-container-lowest/90 · /95`）。
  final double surfaceAlpha;

  /// 底部遮罩渐变的上/中/下三段不透明度（样例 `bg-gradient-to-t`）。
  final double overlayBottomAlpha;
  final double overlayViaAlpha;
  final double overlayTopAlpha;

  /// 遮罩是否用纯黑（居中布局）而非背景色（两侧布局）。
  final bool overlayBlack;

  /// 顶部高光细线强度（样例居中在读卡 `via-white/50` 的 1px 线）。
  final double sheenAlpha;

  /// 悬停态的位移/深度/缩放：居左整卡向外抬升，居右不变换；
  final Offset? hoverOffset;
  final double? hoverDepth;
  final double? hoverScale;

  /// 悬停态的边框不透明度：居左 `0.75`（样例 `.is-hovered`），居右 `0.5`。
  final double? hoverBorderAlpha;

  /// 悬停态卡面整体亮度与模糊：居左 `brightness(1.1)` 且 `blur(0)`。
  final double hoverBrightness;
  final double? hoverBlur;

  /// 悬停态封面自身的缩放与亮度：样例 `group-hover:scale-105` + `brightness-95`。
  final double hoverCoverScale;
  final double hoverCoverBrightness;

  /// 悬停态的位移（未缩放），缺省常态位移。
  Offset get resolvedHoverOffset => hoverOffset ?? offset;

  /// 悬停态的深度，缺省常态深度。
  double get resolvedHoverDepth => hoverDepth ?? depth;

  /// 悬停态的缩放，缺省常态缩放。
  double get resolvedHoverScale => hoverScale ?? scale;

  /// 悬停态的边框不透明度，缺省常态值。
  double get resolvedHoverBorderAlpha => hoverBorderAlpha ?? borderAlpha;

  /// 悬停态的模糊，缺省常态模糊。
  double get resolvedHoverBlur => hoverBlur ?? blur;

  /// 按同一系数放大卡面与档位间距（展开态使用），保持各档比例不变。
  MusicDeckCardSpec zoomed(double factor) {
    if (factor == 1) {
      return this;
    }
    return MusicDeckCardSpec(
      size: size * factor,
      offset: offset * factor,
      depth: depth * factor,
      rotateX: rotateX,
      rotateY: rotateY,
      rotateZ: rotateZ,
      scale: scale,
      opacity: opacity,
      blur: blur,
      radius: radius * factor,
      borderAlpha: borderAlpha,
      ringAlpha: ringAlpha,
      shadowOffset: shadowOffset * factor,
      shadowBlur: shadowBlur * factor,
      shadowAlpha: shadowAlpha,
      shadowSpread: shadowSpread * factor,
      glowAlpha: glowAlpha,
      glowBlur: glowBlur * factor,
      coverContrast: coverContrast,
      coverBrightness: coverBrightness,
      surfaceAlpha: surfaceAlpha,
      overlayBottomAlpha: overlayBottomAlpha,
      overlayViaAlpha: overlayViaAlpha,
      overlayTopAlpha: overlayTopAlpha,
      overlayBlack: overlayBlack,
      sheenAlpha: sheenAlpha,
      hoverOffset: hoverOffset == null ? null : hoverOffset! * factor,
      hoverDepth: hoverDepth == null ? null : hoverDepth! * factor,
      hoverScale: hoverScale,
      hoverBorderAlpha: hoverBorderAlpha,
      hoverBrightness: hoverBrightness,
      hoverBlur: hoverBlur,
      hoverCoverScale: hoverCoverScale,
      hoverCoverBrightness: hoverCoverBrightness,
    );
  }
}

/// 解析某布局指定档位的卡面参数：两侧档位 0..4（0 为在读卡），
MusicDeckCardSpec resolveMusicDeckCard(PortalMusicLayout layout, int slot) {
  switch (layout) {
    case PortalMusicLayout.left:
      return _isometricDeckCard(slot.abs().clamp(0, 4));
    case PortalMusicLayout.right:
      return _steppedDeckCard(slot.abs().clamp(0, 4));
    case PortalMusicLayout.center:
      return _radialDeckCard(slot.clamp(-2, 2));
  }
}

MusicDeckCardSpec _isometricDeckCard(int slot) {
  return MusicDeckCardSpec(
    size: kMusicIsometricCardSize,
    offset: Offset(
      kMusicIsometricShift.dx * slot,
      kMusicIsometricShift.dy * slot,
    ),
    depth: kMusicIsometricDepthStep * slot,
    rotateX: kMusicIsometricRotateX,
    rotateY: kMusicIsometricRotateY,
    rotateZ: kMusicIsometricRotateZ,
    scale: 1 - kMusicIsometricScaleStep * slot,
    opacity: kMusicIsometricOpacities[slot],
    blur: kMusicIsometricBlurs[slot],
    radius: kMusicDeckCardRadius,
    borderAlpha: kMusicIsometricBorderAlphas[slot],
    ringAlpha: kMusicIsometricRingAlphas[slot],
    shadowOffset: Offset(
      kMusicIsometricShadowX[slot],
      kMusicIsometricShadowY[slot],
    ),
    shadowBlur: kMusicIsometricShadowBlur[slot],
    shadowAlpha: kMusicIsometricShadowAlpha[slot],
    shadowSpread: kMusicIsometricShadowSpread[slot],
    glowAlpha: slot == 0 ? kMusicIsometricGlowAlpha : 0,
    glowBlur: kMusicIsometricGlowBlur,
    coverContrast: kMusicIsometricCoverContrast[slot],
    coverBrightness: kMusicIsometricCoverBrightness[slot],
    overlayViaAlpha: kMusicIsometricOverlayViaAlphas[slot],
    hoverOffset: kMusicIsometricHoverOffsets[slot],
    hoverDepth: kMusicIsometricHoverDepths[slot],
    hoverScale: kMusicIsometricHoverScales[slot],
    hoverBorderAlpha: kMusicIsometricHoverBorderAlpha,
    hoverBrightness: kMusicIsometricHoverBrightness,
    // 悬停时去掉虚化：样例 `.is-hovered { filter: blur(0px) ... }`。
    hoverBlur: 0,
    hoverCoverScale: kMusicDeckCardHoverCoverScale,
    hoverCoverBrightness: 1,
  );
}

MusicDeckCardSpec _steppedDeckCard(int slot) {
  return MusicDeckCardSpec(
    size: kMusicSteppedCardSizes[slot],
    offset: Offset(kMusicSteppedShift.dx * slot, kMusicSteppedShift.dy * slot),
    depth: 0,
    rotateX: 0,
    rotateY: 0,
    rotateZ: kMusicSteppedRotateStep * slot,
    scale: 1 - kMusicSteppedScaleStep * slot,
    opacity: kMusicSteppedOpacities[slot],
    blur: 0,
    radius: kMusicDeckCardRadius,
    borderAlpha: kMusicSteppedBorderAlphas[slot],
    ringAlpha: kMusicSteppedRingAlphas[slot],
    shadowOffset: Offset(
      kMusicSteppedShadowX[slot],
      kMusicSteppedShadowY[slot],
    ),
    shadowBlur: kMusicSteppedShadowBlur[slot],
    shadowAlpha: kMusicSteppedShadowAlpha[slot],
    shadowSpread: kMusicSteppedShadowSpread[slot],
    glowAlpha: slot == 0 ? kMusicSteppedGlowAlpha : 0,
    glowBlur: kMusicSteppedGlowBlur,
    coverContrast: kMusicSteppedCoverContrast[slot],
    coverBrightness: kMusicSteppedCoverBrightness[slot],
    overlayViaAlpha: kMusicSteppedOverlayViaAlphas[slot],
    // 居右悬停：非在读卡按样例 JS 抬升 + 描边提亮，在读卡不描边不变换，
    // 只有封面自身的 `group-hover:scale-105 + brightness-95`。
    hoverOffset:
        slot == 0
            ? null
            : Offset(
              kMusicSteppedShift.dx * slot,
              kMusicSteppedShift.dy * slot + kMusicSteppedHoverLift.dy,
            ),
    hoverScale:
        slot == 0
            ? null
            : (1 - kMusicSteppedScaleStep * slot) * kMusicSteppedHoverScale,
    hoverBorderAlpha: slot == 0 ? null : kMusicSteppedHoverBorderAlpha,
    hoverCoverScale: kMusicDeckCardHoverCoverScale,
    hoverCoverBrightness: kMusicDeckCardHoverCoverBrightness,
  );
}

MusicDeckCardSpec _radialDeckCard(int slot) {
  final index = slot + kMusicCenterDeckHalfSlots;
  return MusicDeckCardSpec(
    size: kMusicCenterCardSizes[index],
    offset: Offset(kMusicCenterOffsetsX[index], kMusicCenterOffsetsY[index]),
    depth: 0,
    rotateX: 0,
    rotateY: 0,
    rotateZ: kMusicCenterRotations[index],
    scale: kMusicCenterScales[index],
    opacity: kMusicCenterOpacities[index],
    blur: 0,
    radius: slot == 0 ? kMusicDeckCardRadius : kMusicDeckCardRadiusSmall,
    borderAlpha: kMusicCenterBorderAlphas[index],
    ringAlpha: kMusicCenterRingAlphas[index],
    shadowOffset: Offset(0, kMusicCenterShadowY[index]),
    shadowBlur: kMusicCenterShadowBlur[index],
    shadowAlpha: kMusicCenterShadowAlpha[index],
    shadowSpread: kMusicCenterShadowSpread[index],
    coverContrast: kMusicCenterCoverContrast[index],
    coverBrightness: kMusicCenterCoverBrightness[index],
    surfaceAlpha: kMusicCenterSurfaceAlphas[index],
    overlayBottomAlpha: kMusicCenterOverlayBottomAlphas[index],
    overlayViaAlpha: 0,
    overlayTopAlpha: kMusicCenterOverlayTopAlphas[index],
    overlayBlack: true,
    sheenAlpha: slot == 0 ? 0.5 : 0,
    // 悬停抽出：外侧与内侧后排档沿扇形外向推半个档间距并抬升，读起来才有
    // "把卡片抽出来"的动作；只改封面缩放不足以被察觉（两侧布局同理由）。
    hoverOffset:
        slot == 0
            ? null
            : Offset(
              kMusicCenterOffsetsX[index] + kMusicCenterHoverPullOutX[index],
              kMusicCenterOffsetsY[index] - kMusicCenterHoverLiftY,
            ),
    hoverScale:
        slot == 0 ? null : kMusicCenterScales[index] * kMusicCenterHoverScale,
    hoverBorderAlpha: kMusicCenterHoverBorderAlphas[index],
    hoverCoverScale: kMusicDeckCardHoverCoverScale,
    hoverCoverBrightness: kMusicCenterHoverCoverBrightness[index],
  );
}

/// 卡面装饰层级：样例每档卡片承载的角标与信息带各不相同。
@immutable
class MusicDeckCardChrome {
  const MusicDeckCardChrome({
    required this.heroBadge,
    required this.equalizer,
    required this.indexTag,
    required this.metaBand,
    required this.counterChip,
    required this.counterAlignment,
    required this.padding,
    this.formatTag = false,
  });

  /// 左上「NOW PLAYING」呼吸胶囊（仅两侧布局在读卡）。
  final bool heroBadge;

  /// 右上频谱均衡器条（仅两侧布局在读卡）。
  final bool equalizer;

  /// 右上序号胶囊「NN · 规格」（仅两侧布局非在读卡）。
  final bool indexTag;

  /// 底部信息带：序号玻璃胶囊 + 规格文字 + 曲名 + 艺术家（仅两侧布局）。
  final bool metaBand;

  /// 序号胶囊「NN / NN」（仅居中布局，样例只在角落标序号）。
  final bool counterChip;
  final Alignment counterAlignment;

  /// 右上规格胶囊（仅居中在读卡：样例在读卡右上角单独标「DSD256」）。
  final bool formatTag;

  /// 卡面内边距（两侧 `bottom-4 left-4 right-4` = 16，居中 `top-3 left-3` = 12）。
  final double padding;
}

/// 解析某布局某档位的卡面装饰层级。
MusicDeckCardChrome resolveMusicDeckCardChrome(
  PortalMusicLayout layout, {
  required bool active,
  required int slot,
}) {
  switch (layout) {
    case PortalMusicLayout.left:
    case PortalMusicLayout.right:
      return MusicDeckCardChrome(
        heroBadge: active,
        equalizer: active,
        indexTag: !active,
        metaBand: true,
        counterChip: false,
        counterAlignment: Alignment.topLeft,
        padding: kMusicDeckCardSidePadding,
      );
    case PortalMusicLayout.center:
      // 样例居中卡组只在角落标序号：左半与在读卡贴左上，右半贴右上；
      // 在读卡右上另有规格胶囊（样例「DSD256」）。
      return MusicDeckCardChrome(
        heroBadge: false,
        equalizer: false,
        indexTag: false,
        metaBand: false,
        counterChip: true,
        counterAlignment: slot <= 0 ? Alignment.topLeft : Alignment.topRight,
        formatTag: active,
        padding: kMusicDeckCardCenterPadding,
      );
  }
}

/// 卡组容器的对齐方式：两侧布局贴列起点（样例 `justify-start`），
Alignment musicDeckStageAlignment(PortalMusicLayout layout) {
  return layout == PortalMusicLayout.center
      ? Alignment.center
      : Alignment.centerLeft;
}

/// 卡组容器的纵向定位：样例两侧与居中布局都按容器高度纵向居中。
double musicDeckStageInset(PortalMusicLayout layout) {
  switch (layout) {
    case PortalMusicLayout.left:
      return kMusicIsometricStageInset;
    case PortalMusicLayout.right:
      return kMusicSteppedStageInset;
    case PortalMusicLayout.center:
      return 0;
  }
}

/// 卡组容器的基准尺寸。
Size musicDeckStageSize(PortalMusicLayout layout) {
  switch (layout) {
    case PortalMusicLayout.left:
      return kMusicIsometricStage;
    case PortalMusicLayout.right:
      return kMusicSteppedStage;
    case PortalMusicLayout.center:
      return const Size(kMusicCenterDeckMaxWidth, kMusicCenterDeckHeight);
  }
}

/// 卡组透视距离；右布局为纯 2D 阶梯，不使用透视。
double musicDeckPerspective(PortalMusicLayout layout) {
  switch (layout) {
    case PortalMusicLayout.left:
      return kMusicIsometricPerspective;
    case PortalMusicLayout.right:
      return 0;
    case PortalMusicLayout.center:
      return kMusicCenterPerspective;
  }
}

/// 歌词配色：非在读原文 `on-surface`、译文 `on-surface-variant`、在读原文 `primary`，
const Color kMusicLyricTextColor = Color(0xFFE2E2E6);
const Color kMusicLyricTranslationColor = Color(0xFFC4C7CA);
const Color kMusicLyricActiveTextColor = Color(0xFFFFFFFF);
const Color kMusicLyricSideActiveTranslationColor = Color(0xFFBDC7D4);

/// 在读行时间参考胶囊的底色与描边：样例 `bg-surface-container-lowest/90`
/// 与 `border-white/25`。
const Color kMusicLyricAuxPillFill = Color(0xE60C0E11);
const double kMusicLyricAuxPillBorderAlpha = 0.25;

/// 最远端译文的不透明度（样例两侧 `text-on-surface-variant/70`）。
const double kMusicLyricFarTranslationAlpha = 0.7;

/// 两侧布局其它非在读行的译文不透明度（样例不加压暗，即 `/100`）。
const double kMusicSideLyricTranslationAlpha = 1;

/// 居中布局每一条非在读译文的不透明度（样例统一 `text-on-surface-variant/60`）。
const double kMusicCenterLyricTranslationAlpha = 0.6;

/// 非在读行按与在读行距离取的不透明度档位，索引 0 为紧邻在读行的那一档，
const List<double> kMusicSideLyricBeforeOpacities = <double>[0.40, 0.20];
const List<double> kMusicSideLyricAfterOpacities = <double>[0.50, 0.30, 0.15];
const List<double> kMusicCenterLyricBeforeOpacities = <double>[0.25];
const List<double> kMusicCenterLyricAfterOpacities = <double>[0.30, 0.15];

/// 在读原文的外发光（样例 `drop-shadow-[0_0_blur_rgba(255,255,255,A)]`）。
const double kMusicSideLyricGlowAlpha = 0.22;
const double kMusicSideLyricGlowBlur = 24;
const double kMusicCenterLyricGlowAlpha = 0.4;
const double kMusicCenterLyricGlowBlur = 16;

/// 在读行纵向内边距：左 `py-3.5`、右 `py-3`；居中不做底衬故为 0。
const double kMusicLeftLyricActivePaddingY = 14;
const double kMusicRightLyricActivePaddingY = 12;

/// 歌词区的复刻参数：字号、行距、上下渐隐与在读行装饰。
@immutable
class MusicLyricSpec {
  const MusicLyricSpec({
    required this.fontSize,
    required this.activeFontSize,
    required this.lineHeight,
    required this.activeLineHeight,
    required this.translationFontSize,
    required this.activeTranslationFontSize,
    required this.translationLineHeight,
    required this.activeTranslationLineHeight,
    required this.translationGap,
    required this.activeTranslationGap,
    required this.fontWeight,
    required this.activeFontWeight,
    required this.translationFontWeight,
    required this.activeTranslationFontWeight,
    required this.textColor,
    required this.translationColor,
    required this.activeTextColor,
    required this.activeTranslationColor,
    required this.lineGap,
    required this.activeLinePaddingX,
    required this.activeLinePaddingY,
    required this.activeLineRadius,
    required this.activeLineScale,
    required this.activeLineGlowAlpha,
    required this.activeLineGlowBlur,
    required this.beforeOpacities,
    required this.afterOpacities,
    required this.translationBaseAlpha,
    required this.translationFarAlpha,
    required this.fixedWindowLines,
    required this.mask,
    required this.textAlign,
    required this.blockAnchor,
    required this.activeAuxGap,
    required this.activeAuxReserve,
    required this.activeAuxFontSize,
    required this.activeAuxIconSize,
    required this.activeAuxMinBlockWidth,
    this.activeLineBackgroundColor,
    this.inactiveOpacityScale = 1,
  });

  final double fontSize;
  final double activeFontSize;
  final double lineHeight;
  final double activeLineHeight;
  final double translationFontSize;
  final double activeTranslationFontSize;
  final double translationLineHeight;
  final double activeTranslationLineHeight;
  final double translationGap;
  final double activeTranslationGap;

  /// 字重：两侧非在读 `w300`、居中非在读 `w400`，在读原文统一 `w500`。
  final FontWeight fontWeight;
  final FontWeight activeFontWeight;
  final FontWeight translationFontWeight;
  final FontWeight activeTranslationFontWeight;

  final Color textColor;
  final Color translationColor;
  final Color activeTextColor;
  final Color activeTranslationColor;

  /// 相邻歌词块之间的空隙（样例 `space-y-8` / `space-y-9` / `space-y-3`）。
  final double lineGap;
  final double activeLinePaddingX;
  final double activeLinePaddingY;
  final double activeLineRadius;
  final double activeLineScale;

  /// 在读原文的外发光强度与模糊半径。
  final double activeLineGlowAlpha;
  final double activeLineGlowBlur;

  /// 非在读行按距离取的不透明度档位（索引 0 为紧邻在读行的那一档）。
  final List<double> beforeOpacities;
  final List<double> afterOpacities;

  /// 用户「非当前句透明度」对样例阶梯的整体倍率：1 为样例观感，
  /// 由 [resolveMusicLyricSpec] 按设置值与默认值的比值算出。
  final double inactiveOpacityScale;

  /// 非在读译文的额外压暗系数（近端/远端），见 [translationAlpha]。
  final double translationBaseAlpha;
  final double translationFarAlpha;

  /// 在读行底衬；居中布局不做底衬，故为 null。样例的左侧竖向强调条已整体
  /// 移除（纯音乐等短歌词下只剩一根与内容无关的白线）。
  final Color? activeLineBackgroundColor;

  /// 固定窗口形态的可见行数；两侧布局为 0（沿用设备级滚动偏好）。
  final int fixedWindowLines;
  final (double, double) mask;
  final TextAlign textAlign;
  final Alignment blockAnchor;

  /// 在读行下方时间标签（样例 `lyric-meta`：波形图标 + 行起始时间）与正文的
  /// 间隙，以及它自身的占位高度。居中固定窗口与用户关闭该标签时均为 0；
  /// 行槽等高，因此开启后会计入每一行的高度。
  final double activeAuxGap;
  final double activeAuxReserve;

  /// 时间标签的文字与波形图标字号（样例 `text-[11px]` 与 `text-body-sm`）。
  final double activeAuxFontSize;
  final double activeAuxIconSize;

  /// 时间标签不折行所需的最小文字块宽度：短句的实测块宽会窄于这枚胶囊，
  /// 不抬升块宽会让它溢出行块。未启用时为 0。
  final double activeAuxMinBlockWidth;

  /// 单行内容高度（原文 + 译文），行槽高度在其之上再加 [lineGap]。
  double contentHeight() {
    return math.max(
      activeFontSize * activeLineHeight +
          activeTranslationFontSize * activeTranslationLineHeight +
          activeTranslationGap,
      fontSize * lineHeight +
          translationFontSize * translationLineHeight +
          translationGap,
    );
  }

  /// 行槽高度：内容高度 + 行距空隙。
  double slotHeight() => contentHeight() + lineGap;

  /// 非在读译文的额外压暗系数：两侧仅最前行压到 `/70`，居中每行压到 `/60`。
  double translationAlpha(int relative) {
    final isFar = relative < 0 && relative.abs() >= beforeOpacities.length;
    return isFar ? translationFarAlpha : translationBaseAlpha;
  }
}

/// 非在读行按与在读行的距离取的不透明度；在读行为满亮。
///
/// 样例档位再乘用户的「非当前句透明度」倍率，并留 0.05 下限，避免把整块
/// 歌词压到不可读。
double musicLyricLineOpacity(MusicLyricSpec spec, int relative) {
  if (relative == 0) {
    return 1;
  }
  final steps = relative < 0 ? spec.beforeOpacities : spec.afterOpacities;
  if (steps.isEmpty) {
    return 1;
  }
  final index = (relative.abs() - 1).clamp(0, steps.length - 1);
  return (steps[index] * spec.inactiveOpacityScale).clamp(0.05, 1.0).toDouble();
}

/// 解析某布局的歌词区复刻参数（按 [scale] 等比换算）。
///
/// [activeFontSizePx] / [inactiveFontSizePx] 为用户在视觉编辑中设定的字号
/// （px）；留空时跟随该布局的样例基准。译文等派生尺寸按「设定值 / 基准值」
/// 的同一比值缩放，保证只改字号不破样例排版比例。
/// [inactiveOpacity] 为用户的「非当前句透明度」，换算成样例透明度阶梯的倍率，
/// 未设置时与样例观感一致。[lineSpacing] 为行距倍率，作用于相邻歌词块的间隙
/// （在读行的底衬内边距不随之缩放，否则高亮带会随行距变形）。
MusicLyricSpec resolveMusicLyricSpec(
  PortalMusicLayout layout,
  double scale, {
  int? activeFontSizePx,
  int? inactiveFontSizePx,
  double? inactiveOpacity,
  double lineSpacing = 1,
  bool timeTagEnabled = false,
  bool deckEnabled = true,
}) {
  final isCenter = layout == PortalMusicLayout.center;
  // 居中构图只有在堆叠卡片可见时使用固定三行窗口；关闭卡组后歌词改为滚动列，
  // 与两侧布局同一形态（居左、同一渐隐要带），由 fixedWindowLines == 0 表达。
  final centerFixedWindow = isCenter && deckEnabled;
  // 时间标签是用户开关项（默认关闭），关闭后连同其预留高度一并归零，
  // 行槽与渲染共用同一判据。
  final showTimeTag = timeTagEnabled && !isCenter;
  final (baseActive, baseInactive) = musicLyricBaseFontSizes(layout);
  final activeRatio = (activeFontSizePx ?? baseActive) / baseActive;
  final inactiveRatio = (inactiveFontSizePx ?? baseInactive) / baseInactive;
  // 锚点而非默认值：默认值调整不应改变既有用户已保存设置对应的观感。
  final opacityScale =
      (inactiveOpacity ?? kMusicLyricLadderOpacityAnchor) /
      kMusicLyricLadderOpacityAnchor;
  double px(double value) => value * scale;
  double pxInactive(double value) => value * scale * inactiveRatio;
  double pxActive(double value) => value * scale * activeRatio;
  return MusicLyricSpec(
    fontSize: pxInactive(isCenter ? 14 : 18),
    activeFontSize: pxActive(isCenter ? 18 : 44),
    lineHeight: isCenter ? 20 / 14 : 26 / 18,
    activeLineHeight: isCenter ? 26 / 18 : 52 / 44,
    translationFontSize: pxInactive(isCenter ? 11 : 12),
    activeTranslationFontSize: pxActive(isCenter ? 12 : 16),
    translationLineHeight: isCenter ? 14 / 11 : 18 / 12,
    activeTranslationLineHeight: isCenter ? 18 / 12 : 24 / 16,
    translationGap: px(isCenter ? 2 : 4),
    activeTranslationGap: px(isCenter ? 4 : 6),
    fontWeight: isCenter ? FontWeight.w400 : FontWeight.w300,
    activeFontWeight: FontWeight.w500,
    translationFontWeight: isCenter ? FontWeight.w400 : FontWeight.w300,
    activeTranslationFontWeight: isCenter ? FontWeight.w400 : FontWeight.w300,
    textColor: kMusicLyricTextColor,
    translationColor: kMusicLyricTranslationColor,
    activeTextColor: kMusicLyricActiveTextColor,
    activeTranslationColor:
        isCenter
            ? kMusicLyricTranslationColor
            : kMusicLyricSideActiveTranslationColor,
    // 样例把两侧布局的行间隙写死为 space-y-8/9（32/36px）；在读行还另有上下
    // 内边距，叠加后视觉上明显偏松，因此基准收到 18/20，并交给行距倍率调节。
    // 关卡组后的居中滚动列与两侧同形态，因此用两侧的行距与在读行样式。
    lineGap: px(
      (centerFixedWindow
              ? 12
              : layout == PortalMusicLayout.right
              ? 20
              : 18) *
          lineSpacing,
    ),
    activeLinePaddingX: px(16),
    activeLinePaddingY:
        centerFixedWindow
            ? 0
            : px(
              layout == PortalMusicLayout.right
                  ? kMusicRightLyricActivePaddingY
                  : kMusicLeftLyricActivePaddingY,
            ),
    activeLineRadius: px(12),
    activeLineScale: centerFixedWindow ? 1.04 : 1,
    activeLineGlowAlpha:
        centerFixedWindow
            ? kMusicCenterLyricGlowAlpha
            : kMusicSideLyricGlowAlpha,
    activeLineGlowBlur:
        centerFixedWindow ? kMusicCenterLyricGlowBlur : kMusicSideLyricGlowBlur,
    beforeOpacities:
        isCenter
            ? kMusicCenterLyricBeforeOpacities
            : kMusicSideLyricBeforeOpacities,
    afterOpacities:
        isCenter
            ? kMusicCenterLyricAfterOpacities
            : kMusicSideLyricAfterOpacities,
    translationBaseAlpha:
        isCenter
            ? kMusicCenterLyricTranslationAlpha
            : kMusicSideLyricTranslationAlpha,
    translationFarAlpha:
        isCenter
            ? kMusicCenterLyricTranslationAlpha
            : kMusicLyricFarTranslationAlpha,
    activeLineBackgroundColor:
        centerFixedWindow ? null : const Color(0x660C0E11),
    fixedWindowLines: centerFixedWindow ? 3 : 0,
    // 关闭卡组的居中构图是通高滚动视口，沿用两侧已调校过的渐隐要带；
    // 小窗的 0.22/0.78 放进通高视口会把上半段整片压暗。
    mask:
        isCenter
            ? centerFixedWindow
                ? kMusicCenterLyricMask
                : kMusicLeftLyricMask
            : layout == PortalMusicLayout.right
            ? kMusicRightLyricMask
            : kMusicLeftLyricMask,
    textAlign: centerFixedWindow ? TextAlign.center : TextAlign.left,
    blockAnchor: centerFixedWindow ? Alignment.center : Alignment.centerLeft,
    // 在读行底部时间标签：样例 `lyric-meta` 的 `mt-3` + `py-1` 胶囊。
    // 居中构图没有这一行（样例如此），用户开关关闭时同样归零。
    activeAuxGap: showTimeTag ? px(12) : 0,
    activeAuxReserve: showTimeTag ? px(22) : 0,
    activeAuxFontSize: showTimeTag ? px(11) : 0,
    activeAuxIconSize: showTimeTag ? px(12) : 0,
    // 胶囊（内边距 + 图标 + 时间戳）的固定宽度：统一块宽必须不低于它，
    // 否则短句的时间标签会溢出行块。
    activeAuxMinBlockWidth: showTimeTag ? px(124) : 0,
    inactiveOpacityScale: opacityScale,
  );
}

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
