part of 'music_immersive_layout_spec.dart';

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
