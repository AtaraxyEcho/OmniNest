import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:omninest/core/widgets/responsive_breakpoints.dart';

/// 天气详情弹窗布局档位。
enum WeatherDetailLayoutMode {
  /// 手机：单列，卡片纵向堆叠。
  mobile,

  /// 平板：英雄区双列，指标 3 列。
  tablet,

  /// 桌面：英雄区双列，指标 3 列，整体更宽松。
  desktop,
}

/// 对齐样例 max-w-3xl 的玻璃面板宽度。
const double kWeatherDetailMaxWidth = 768;

/// 天气详情弹窗的响应式度量。
///
/// 以程序窗口为输入，输出保证 dialog 宽高不超过可用视口。
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
    required this.cardPadding,
    required this.tempFontSize,
    required this.closeButtonSize,
    required this.cornerRadius,
    required this.compactHeight,
    required this.heroMinHeight,
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

    final baseHInset = switch (mode) {
      WeatherDetailLayoutMode.mobile => 10.0,
      WeatherDetailLayoutMode.tablet => 16.0,
      WeatherDetailLayoutMode.desktop => 20.0,
    };
    final baseVInset = switch (mode) {
      WeatherDetailLayoutMode.mobile => 10.0,
      WeatherDetailLayoutMode.tablet => 14.0,
      WeatherDetailLayoutMode.desktop => 18.0,
    };
    final horizontalInset = math.min(baseHInset, width * 0.05);
    final verticalInset = math.min(baseVInset, height * 0.04);

    final availableWidth = math.min(width - horizontalInset * 2, width);
    final availableHeight = math.min(height - verticalInset * 2, height);
    final safeWidth = math.max(240.0, availableWidth);
    final safeHeight = math.max(280.0, availableHeight);

    final dialogWidth = math.min(kWeatherDetailMaxWidth, safeWidth);
    // 高度贴近内容，上限约 92% 可用高，避免盖满整页。
    final dialogHeight = math.min(safeHeight * 0.94, safeHeight);

    final useHeroSplit =
        mode != WeatherDetailLayoutMode.mobile &&
        dialogWidth >= 520 &&
        !compactHeight;

    final metricColumns = switch (mode) {
      WeatherDetailLayoutMode.mobile => dialogWidth >= 340 ? 2 : 1,
      WeatherDetailLayoutMode.tablet => 3,
      WeatherDetailLayoutMode.desktop => 3,
    };

    final sectionGap = tight || compactHeight ? 10.0 : 12.0;
    final pad = (mode == WeatherDetailLayoutMode.mobile ? 14.0 : 16.0).clamp(
      10.0,
      dialogWidth * 0.05,
    );
    final contentPadding = EdgeInsets.all(pad);

    final cardPadding =
        compactHeight
            ? const EdgeInsets.symmetric(horizontal: 12, vertical: 12)
            : const EdgeInsets.symmetric(horizontal: 14, vertical: 14);

    // 样例 clamp(4rem, 12vw, 6rem)，按弹窗宽近似折算。
    final tempFontSize = (dialogWidth * 0.14).clamp(48.0, 88.0);

    final closeButtonSize = tight ? 32.0 : 36.0;
    final cornerRadius = 24.0;
    final heroMinHeight = useHeroSplit ? 168.0 : 150.0;

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
      cardPadding: cardPadding,
      tempFontSize: tempFontSize,
      closeButtonSize: closeButtonSize,
      cornerRadius: cornerRadius,
      compactHeight: compactHeight,
      heroMinHeight: heroMinHeight,
    );
  }

  static WeatherDetailLayoutMode _resolveMode(double width) {
    if (ResponsiveBreakpoints.isMobile(width)) {
      return WeatherDetailLayoutMode.mobile;
    }
    if (ResponsiveBreakpoints.isTablet(width)) {
      return WeatherDetailLayoutMode.tablet;
    }
    return WeatherDetailLayoutMode.desktop;
  }

  final WeatherDetailLayoutMode mode;
  final double dialogWidth;
  final double dialogHeight;
  final EdgeInsets insetPadding;
  final EdgeInsets contentPadding;
  final bool useHeroSplit;
  final int metricColumns;
  final double sectionGap;
  final EdgeInsets cardPadding;
  final double tempFontSize;
  final double closeButtonSize;
  final double cornerRadius;
  final bool compactHeight;
  final double heroMinHeight;

  bool get isMobile => mode == WeatherDetailLayoutMode.mobile;

  double scaledTempSize(TextScaler scaler) {
    return scaler.scale(tempFontSize).clamp(40.0, tempFontSize * 1.25);
  }
}
