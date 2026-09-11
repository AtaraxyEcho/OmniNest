import 'package:flutter/material.dart';
import 'package:omninest/app/theme/global_theme_colors.dart';

/// 移动端工作台使用的尺寸与动效令牌。
abstract final class MobileLayoutTokens {
  static const double horizontalPadding = 16;
  static const double tabletHorizontalPadding = 24;
  static const double sectionGap = 24;
  static const double itemGap = 12;
  static const double radius = 8;
  static const double minimumTarget = 48;
  static const double listRowHeight = 64;

  /// 平板及以上壳层内容（底栏 tab 组、迷你播放条、顶栏搜索框）的最大
  /// 宽度：超出部分两侧留白交给壁纸/玻璃，避免控件被整屏拉伸。
  static const double chromeMaxWidth = 720;

  /// 达到该宽度后顶栏展示展开搜索框（替代标题右侧的搜索图标）。
  static const double topBarSearchMinWidth = 840;

  /// 展开搜索框的最大宽度：平板整条顶栏直接拉满会压过标题与操作区。
  static const double topBarSearchMaxWidth = 460;

  static const Duration pressDuration = Duration(milliseconds: 120);
  static const Duration stateDuration = Duration(milliseconds: 190);
  static const Duration pageDuration = Duration(milliseconds: 240);
  static const Curve motionCurve = Curves.easeOutCubic;

  static EdgeInsets pagePadding(BuildContext context) {
    return EdgeInsets.symmetric(
      horizontal:
          MediaQuery.sizeOf(context).width >= 600
              ? tabletHorizontalPadding
              : horizontalPadding,
    );
  }
}

@immutable
class MobileSemanticColors {
  const MobileSemanticColors({
    required this.pageMask,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceSelected,
    required this.textPrimary,
    required this.textSecondary,
    required this.outline,
    required this.musicAccent,
    required this.warmAccent,
    required this.danger,
    required this.success,
  });

  final Color pageMask;
  final Color surface;
  final Color surfaceRaised;
  final Color surfaceSelected;
  final Color textPrimary;
  final Color textSecondary;
  final Color outline;
  final Color musicAccent;
  final Color warmAccent;
  final Color danger;
  final Color success;
}

extension MobileThemeContext on BuildContext {
  MobileSemanticColors get mobileColors {
    final scheme = Theme.of(this).colorScheme;
    final semantic = Theme.of(this).extension<GlobalThemeColors>();
    return MobileSemanticColors(
      pageMask: scheme.surface,
      surface: scheme.surfaceContainerLow,
      surfaceRaised: scheme.surfaceContainer,
      surfaceSelected: scheme.primaryContainer,
      textPrimary: scheme.onSurface,
      textSecondary: scheme.onSurfaceVariant,
      outline: scheme.outlineVariant,
      musicAccent: scheme.primary,
      warmAccent: scheme.tertiary,
      danger: scheme.error,
      success: semantic?.success ?? scheme.primary,
    );
  }
}
