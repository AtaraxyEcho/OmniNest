import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:omninest/core/widgets/responsive_breakpoints.dart';

/// 天气详情弹窗布局档位。
enum WeatherDetailLayoutMode {
  /// 手机：单列。
  mobile,

  /// 平板及以上：英雄区双列。
  tablet,

  /// 桌面：英雄区双列，间距略宽。
  desktop,
}

/// 对齐样例 max-w-3xl。
const double kWeatherDetailMaxWidth = 768;

/// 样例 min-h-[180px]。
const double kWeatherDetailHeroMinHeight = 180;

/// 天气详情弹窗度量。
///
/// 宽高均不超过可用视口；高度只作上限，内容高度贴合卡片。
@immutable
class WeatherDetailLayoutMetrics {
  const WeatherDetailLayoutMetrics({
    required this.mode,
    required this.dialogWidth,
    required this.dialogHeight,
    required this.insetPadding,
    required this.contentPadding,
    required this.useHeroSplit,
    required this.metricColumns,
    required this.sectionGap,
    required this.heroCardPadding,
    required this.tempFontSize,
    required this.closeButtonSize,
    required this.cornerRadius,
    required this.innerRadius,
    required this.compactHeight,
    required this.heroHeight,
    required this.splitCardHeight,
  });

  factory WeatherDetailLayoutMetrics.resolve(Size viewport) {
    final width =
        viewport.width.isFinite && viewport.width > 0 ? viewport.width : 390.0;
    final height =
        viewport.height.isFinite && viewport.height > 0
            ? viewport.height
            : 844.0;

    final mode = _resolveMode(width);
    final compactHeight = height < 700;
    final tight = width < 360 || height < 480;

    // 样例外层边距：手机贴边略留，桌面适中。
    final horizontalInset = switch (mode) {
      WeatherDetailLayoutMode.mobile => 12.0,
      WeatherDetailLayoutMode.tablet => 20.0,
      WeatherDetailLayoutMode.desktop => 24.0,
    };
    final verticalInset = switch (mode) {
      WeatherDetailLayoutMode.mobile => 12.0,
      WeatherDetailLayoutMode.tablet => 16.0,
      WeatherDetailLayoutMode.desktop => 20.0,
    };

    final availableWidth = math.min(
      math.max(240.0, width - horizontalInset * 2),
      width,
    );
    final availableHeight = math.min(
      math.max(280.0, height - verticalInset * 2),
      height,
    );

    final dialogWidth = math.min(kWeatherDetailMaxWidth, availableWidth);
    // 仅作滚动上限；面板本身贴内容高度。
    final dialogHeight = availableHeight;

    final useHeroSplit =
        mode != WeatherDetailLayoutMode.mobile &&
        dialogWidth >= 560 &&
        !compactHeight;

    final metricColumns = dialogWidth >= 420 ? 3 : 2;

    // 样例 gap-4 / p-4~6。
    final sectionGap = tight ? 12.0 : 16.0;
    final contentPad = switch (mode) {
      WeatherDetailLayoutMode.mobile => 16.0,
      WeatherDetailLayoutMode.tablet => 20.0,
      WeatherDetailLayoutMode.desktop => 24.0,
    };
    final contentPadding = EdgeInsets.all(
      contentPad.clamp(12.0, dialogWidth * 0.06),
    );

    // 样例左卡 p-5 sm:p-6。
    final heroCardPadding =
        compactHeight
            ? const EdgeInsets.symmetric(horizontal: 16, vertical: 16)
            : const EdgeInsets.symmetric(horizontal: 20, vertical: 20);

    // 样例 clamp(4rem, 12vw, 6rem)，以面板宽近似。
    final tempFontSize = (dialogWidth * 0.12).clamp(64.0, 96.0);

    final closeButtonSize = tight ? 32.0 : 36.0;
    const cornerRadius = 24.0;
    const innerRadius = 16.0;

    // 双列时左右等高：左 min-h 180，右侧两卡均分。
    final heroHeight =
        useHeroSplit
            ? math.max(kWeatherDetailHeroMinHeight, tempFontSize * 1.85 + 48)
            : math.max(160.0, tempFontSize * 1.55 + 40);
    final splitCardHeight =
        useHeroSplit ? (heroHeight - sectionGap * 0.75) / 2 : 88.0;

    return WeatherDetailLayoutMetrics(
      mode: mode,
      dialogWidth: dialogWidth,
      dialogHeight: dialogHeight,
      insetPadding: EdgeInsets.symmetric(
        horizontal: horizontalInset,
        vertical: verticalInset,
      ),
      contentPadding: contentPadding,
      useHeroSplit: useHeroSplit,
      metricColumns: metricColumns,
      sectionGap: sectionGap,
      heroCardPadding: heroCardPadding,
      tempFontSize: tempFontSize,
      closeButtonSize: closeButtonSize,
      cornerRadius: cornerRadius,
      innerRadius: innerRadius,
      compactHeight: compactHeight,
      heroHeight: heroHeight,
      splitCardHeight: splitCardHeight,
    );
  }

  static WeatherDetailLayoutMode _resolveMode(double width) {
    if (ResponsiveBreakpoints.isMobile(width)) {
      return WeatherDetailLayoutMode.mobile;
    }
    if (width >= ResponsiveBreakpoints.desktop) {
      return WeatherDetailLayoutMode.desktop;
    }
    return WeatherDetailLayoutMode.tablet;
  }

  final WeatherDetailLayoutMode mode;
  final double dialogWidth;
  final double dialogHeight;
  final EdgeInsets insetPadding;
  final EdgeInsets contentPadding;
  final bool useHeroSplit;
  final int metricColumns;
  final double sectionGap;
  final EdgeInsets heroCardPadding;
  final double tempFontSize;
  final double closeButtonSize;
  final double cornerRadius;
  final double innerRadius;
  final bool compactHeight;
  final double heroHeight;
  final double splitCardHeight;

  bool get isMobile => mode == WeatherDetailLayoutMode.mobile;

  double scaledTempSize(TextScaler scaler) {
    return scaler.scale(tempFontSize).clamp(48.0, tempFontSize * 1.2);
  }
}
