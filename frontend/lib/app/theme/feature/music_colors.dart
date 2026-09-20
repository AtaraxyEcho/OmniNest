import 'package:flutter/material.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/app/theme/global_theme_colors.dart';

@immutable
class MusicColors extends ThemeExtension<MusicColors> {
  const MusicColors({
    required this.surface,
    required this.background,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.primary,
    required this.brandRed,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.outline,
    // Hero Banner
    required this.heroGradientStart,
    required this.heroGradientCenter,
    required this.heroGradientEnd,
    required this.heroOverlayStart,
    required this.heroOverlayEnd,
    required this.heroTextColor,
    required this.heroTextSecondary,
    // 卡片
    required this.cardBorderRadius,
    required this.cardBorder,
    required this.cardBorderHover,
    required this.albumHoverOverlay,
    // 琉璃特效
    required this.showGlassEffect,
    required this.glassBlurSigma,
    required this.glassBorderStart,
    required this.glassBorderEnd,
    // 晨霜毛玻璃
    required this.mistBlob1,
    required this.mistBlob2,
    required this.mistBlob3,
    required this.mistBase,
    required this.glassBg,
    required this.glassBorder,
    required this.rowHoverShadowColor,
    // 选中状态
    required this.selectedBg,
    required this.selectedBorder,
    required this.selectedShadowColor,
    // 曲目行状态：播放（持久激活）与悬停（瞬态浏览）必须满足权重阶梯
    required this.playingRowBg,
    required this.hoverBg,
    // 语义化覆盖层
    required this.overlay,
    required this.overlayLight,
    required this.shadow,
    required this.badgeBg,
    required this.badgeText,
    required this.danger,
    required this.star,
    required this.discBg,
    required this.discCenter,
  });

  final Color surface;
  final Color background;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color primary;
  final Color brandRed;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color outline;
  // Hero Banner
  final Color heroGradientStart;
  final Color heroGradientCenter;
  final Color heroGradientEnd;
  final Color heroOverlayStart;
  final Color heroOverlayEnd;
  final Color heroTextColor;
  final Color heroTextSecondary;
  // 卡片
  final double cardBorderRadius;
  final Color cardBorder;
  final Color cardBorderHover;
  final Color albumHoverOverlay;
  // 琉璃特效
  final bool showGlassEffect;
  final double glassBlurSigma;
  final Color glassBorderStart;
  final Color glassBorderEnd;
  // 晨霜毛玻璃
  final Color mistBlob1;
  final Color mistBlob2;
  final Color mistBlob3;
  final Color mistBase;
  final Color glassBg;
  final Color glassBorder;
  final Color rowHoverShadowColor;
  // 选中状态
  final Color selectedBg;
  final Color selectedBorder;
  final Color selectedShadowColor;
  // 曲目行状态：播放行为持久激活态、悬停为瞬态反馈，强度阶梯 hoverBg < playingRowBg
  final Color playingRowBg;
  final Color hoverBg;
  // 语义化覆盖层
  final Color overlay;
  final Color overlayLight;
  final Color shadow;
  final Color badgeBg;
  final Color badgeText;
  final Color danger;
  final Color star;
  final Color discBg;
  final Color discCenter;

  /// 从全局主题色派生 Music 模块专属色
  ///
  /// 所有模块共享同一个 GlobalThemeColors 基调，
  /// Music 专属 token（hero banner、glass 效果等）从基调派生。
  factory MusicColors.fromGlobal(GlobalThemeColors base) {
    final light =
        ThemeData.estimateBrightnessForColor(base.surface) == Brightness.light;
    final surface =
        light
            ? Color.lerp(base.surfaceContainerLow, base.primaryContainer, 0.06)!
            : base.surface;
    final background =
        light
            ? Color.lerp(base.surface, base.primaryContainer, 0.04)!
            : base.surfaceContainerLowest;
    final surfaceContainer =
        light
            ? Color.lerp(
              base.surfaceContainerHigh,
              base.primaryContainer,
              0.10,
            )!
            : base.surfaceContainer;
    final surfaceContainerHigh =
        light
            ? Color.lerp(
              base.surfaceContainerHighest,
              base.secondaryContainer,
              0.08,
            )!
            : base.surfaceContainerHigh;
    return MusicColors(
      surface: surface,
      background: background,
      surfaceContainer: surfaceContainer,
      surfaceContainerHigh: surfaceContainerHigh,
      primary: base.primary,
      brandRed: base.error,
      onSurface: base.onSurface,
      onSurfaceVariant: base.onSurfaceVariant,
      outline: base.outlineVariant,
      // Hero Banner — 从 primary 和 surface 派生
      heroGradientStart: background,
      heroGradientCenter: surface,
      heroGradientEnd: surfaceContainer,
      heroOverlayStart: base.overlay,
      heroOverlayEnd: base.overlayLight,
      heroTextColor: base.onSurface,
      heroTextSecondary: base.onSurfaceVariant,
      // 卡片
      cardBorderRadius: 12,
      cardBorder: Color.lerp(Colors.transparent, base.outlineVariant, 0.06)!,
      cardBorderHover: Color.lerp(Colors.transparent, base.primary, 0.16)!,
      albumHoverOverlay: base.hoverOverlay,
      // 琉璃特效 — 默认关闭，变体可覆盖
      showGlassEffect: false,
      glassBlurSigma: 0,
      glassBorderStart: Colors.transparent,
      glassBorderEnd: Colors.transparent,
      mistBlob1: Colors.transparent,
      mistBlob2: Colors.transparent,
      mistBlob3: Colors.transparent,
      mistBase: base.surface,
      glassBg: Colors.transparent,
      glassBorder: Colors.transparent,
      rowHoverShadowColor: Colors.transparent,
      // 选中状态
      selectedBg: base.selectedOverlay,
      selectedBorder: Color.lerp(Colors.transparent, base.primary, 0.3)!,
      selectedShadowColor: Color.lerp(Colors.transparent, base.primary, 0.2)!,
      // 曲目行状态：播放行随明暗缩放主色强度（深色 24% / 浅色 14%），
      // 悬停直接沿用全局悬停 tint，与专辑卡悬停语言保持一致。
      playingRowBg: base.primary.withValues(alpha: light ? 0.14 : 0.24),
      hoverBg: base.hoverOverlay,
      // 语义化覆盖层
      overlay: base.overlay,
      overlayLight: base.overlayLight,
      shadow: base.shadow,
      badgeBg: base.badgeBg,
      badgeText: base.badgeText,
      danger: base.error,
      star: base.star,
      discBg: base.surfaceContainerHighest,
      discCenter: base.surfaceContainerHigh,
    );
  }

  static const List<MusicColors> values = [];

  @override
  MusicColors copyWith({
    Color? surface,
    Color? background,
    Color? surfaceContainer,
    Color? surfaceContainerHigh,
    Color? primary,
    Color? brandRed,
    Color? onSurface,
    Color? onSurfaceVariant,
    Color? outline,
    Color? heroGradientStart,
    Color? heroGradientCenter,
    Color? heroGradientEnd,
    Color? heroOverlayStart,
    Color? heroOverlayEnd,
    Color? heroTextColor,
    Color? heroTextSecondary,
    double? cardBorderRadius,
    Color? cardBorder,
    Color? cardBorderHover,
    Color? albumHoverOverlay,
    bool? showGlassEffect,
    double? glassBlurSigma,
    Color? glassBorderStart,
    Color? glassBorderEnd,
    Color? mistBlob1,
    Color? mistBlob2,
    Color? mistBlob3,
    Color? mistBase,
    Color? glassBg,
    Color? glassBorder,
    Color? rowHoverShadowColor,
    Color? selectedBg,
    Color? selectedBorder,
    Color? selectedShadowColor,
    Color? playingRowBg,
    Color? hoverBg,
    Color? overlay,
    Color? overlayLight,
    Color? shadow,
    Color? badgeBg,
    Color? badgeText,
    Color? danger,
    Color? star,
    Color? discBg,
    Color? discCenter,
  }) {
    return MusicColors(
      surface: surface ?? this.surface,
      background: background ?? this.background,
      surfaceContainer: surfaceContainer ?? this.surfaceContainer,
      surfaceContainerHigh: surfaceContainerHigh ?? this.surfaceContainerHigh,
      primary: primary ?? this.primary,
      brandRed: brandRed ?? this.brandRed,
      onSurface: onSurface ?? this.onSurface,
      onSurfaceVariant: onSurfaceVariant ?? this.onSurfaceVariant,
      outline: outline ?? this.outline,
      heroGradientStart: heroGradientStart ?? this.heroGradientStart,
      heroGradientCenter: heroGradientCenter ?? this.heroGradientCenter,
      heroGradientEnd: heroGradientEnd ?? this.heroGradientEnd,
      heroOverlayStart: heroOverlayStart ?? this.heroOverlayStart,
      heroOverlayEnd: heroOverlayEnd ?? this.heroOverlayEnd,
      heroTextColor: heroTextColor ?? this.heroTextColor,
      heroTextSecondary: heroTextSecondary ?? this.heroTextSecondary,
      cardBorderRadius: cardBorderRadius ?? this.cardBorderRadius,
      cardBorder: cardBorder ?? this.cardBorder,
      cardBorderHover: cardBorderHover ?? this.cardBorderHover,
      albumHoverOverlay: albumHoverOverlay ?? this.albumHoverOverlay,
      showGlassEffect: showGlassEffect ?? this.showGlassEffect,
      glassBlurSigma: glassBlurSigma ?? this.glassBlurSigma,
      glassBorderStart: glassBorderStart ?? this.glassBorderStart,
      glassBorderEnd: glassBorderEnd ?? this.glassBorderEnd,
      mistBlob1: mistBlob1 ?? this.mistBlob1,
      mistBlob2: mistBlob2 ?? this.mistBlob2,
      mistBlob3: mistBlob3 ?? this.mistBlob3,
      mistBase: mistBase ?? this.mistBase,
      glassBg: glassBg ?? this.glassBg,
      glassBorder: glassBorder ?? this.glassBorder,
      rowHoverShadowColor: rowHoverShadowColor ?? this.rowHoverShadowColor,
      selectedBg: selectedBg ?? this.selectedBg,
      selectedBorder: selectedBorder ?? this.selectedBorder,
      selectedShadowColor: selectedShadowColor ?? this.selectedShadowColor,
      playingRowBg: playingRowBg ?? this.playingRowBg,
      hoverBg: hoverBg ?? this.hoverBg,
      overlay: overlay ?? this.overlay,
      overlayLight: overlayLight ?? this.overlayLight,
      shadow: shadow ?? this.shadow,
      badgeBg: badgeBg ?? this.badgeBg,
      badgeText: badgeText ?? this.badgeText,
      danger: danger ?? this.danger,
      star: star ?? this.star,
      discBg: discBg ?? this.discBg,
      discCenter: discCenter ?? this.discCenter,
    );
  }

  @override
  MusicColors lerp(MusicColors? other, double t) {
    if (other is! MusicColors) return this;
    return MusicColors(
      surface: Color.lerp(surface, other.surface, t)!,
      background: Color.lerp(background, other.background, t)!,
      surfaceContainer:
          Color.lerp(surfaceContainer, other.surfaceContainer, t)!,
      surfaceContainerHigh:
          Color.lerp(surfaceContainerHigh, other.surfaceContainerHigh, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      brandRed: Color.lerp(brandRed, other.brandRed, t)!,
      onSurface: Color.lerp(onSurface, other.onSurface, t)!,
      onSurfaceVariant:
          Color.lerp(onSurfaceVariant, other.onSurfaceVariant, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      heroGradientStart:
          Color.lerp(heroGradientStart, other.heroGradientStart, t)!,
      heroGradientCenter:
          Color.lerp(heroGradientCenter, other.heroGradientCenter, t)!,
      heroGradientEnd: Color.lerp(heroGradientEnd, other.heroGradientEnd, t)!,
      heroOverlayStart:
          Color.lerp(heroOverlayStart, other.heroOverlayStart, t)!,
      heroOverlayEnd: Color.lerp(heroOverlayEnd, other.heroOverlayEnd, t)!,
      heroTextColor: Color.lerp(heroTextColor, other.heroTextColor, t)!,
      heroTextSecondary:
          Color.lerp(heroTextSecondary, other.heroTextSecondary, t)!,
      cardBorderRadius:
          cardBorderRadius + (other.cardBorderRadius - cardBorderRadius) * t,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
      cardBorderHover: Color.lerp(cardBorderHover, other.cardBorderHover, t)!,
      albumHoverOverlay:
          Color.lerp(albumHoverOverlay, other.albumHoverOverlay, t)!,
      showGlassEffect: t < 0.5 ? showGlassEffect : other.showGlassEffect,
      glassBlurSigma:
          glassBlurSigma + (other.glassBlurSigma - glassBlurSigma) * t,
      glassBorderStart:
          Color.lerp(glassBorderStart, other.glassBorderStart, t)!,
      glassBorderEnd: Color.lerp(glassBorderEnd, other.glassBorderEnd, t)!,
      mistBlob1: Color.lerp(mistBlob1, other.mistBlob1, t)!,
      mistBlob2: Color.lerp(mistBlob2, other.mistBlob2, t)!,
      mistBlob3: Color.lerp(mistBlob3, other.mistBlob3, t)!,
      mistBase: Color.lerp(mistBase, other.mistBase, t)!,
      glassBg: Color.lerp(glassBg, other.glassBg, t)!,
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
      rowHoverShadowColor:
          Color.lerp(rowHoverShadowColor, other.rowHoverShadowColor, t)!,
      selectedBg: Color.lerp(selectedBg, other.selectedBg, t)!,
      selectedBorder: Color.lerp(selectedBorder, other.selectedBorder, t)!,
      selectedShadowColor:
          Color.lerp(selectedShadowColor, other.selectedShadowColor, t)!,
      playingRowBg: Color.lerp(playingRowBg, other.playingRowBg, t)!,
      hoverBg: Color.lerp(hoverBg, other.hoverBg, t)!,
      overlay: Color.lerp(overlay, other.overlay, t)!,
      overlayLight: Color.lerp(overlayLight, other.overlayLight, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      badgeBg: Color.lerp(badgeBg, other.badgeBg, t)!,
      badgeText: Color.lerp(badgeText, other.badgeText, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      star: Color.lerp(star, other.star, t)!,
      discBg: Color.lerp(discBg, other.discBg, t)!,
      discCenter: Color.lerp(discCenter, other.discCenter, t)!,
    );
  }
}

extension MusicColorsX on BuildContext {
  MusicColors get musicColors {
    final theme = Theme.of(this);
    return theme.extension<MusicColors>() ??
        MusicColors.fromGlobal(
          theme.brightness == Brightness.dark
              ? AppThemePalette.dark
              : AppThemePalette.light,
        );
  }
}
