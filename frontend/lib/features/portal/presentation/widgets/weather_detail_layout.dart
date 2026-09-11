import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:omninest/core/widgets/responsive_breakpoints.dart';

/// 天气详情弹窗布局档位。
enum WeatherDetailLayoutMode {
  /// 手机：单列紧凑，贴边填充。
  mobile,

  /// 平板：双列主次分区，指标三列。
  tablet,

  /// 桌面：双列英雄区 + 侧栏，指标三列。
  desktop,

  /// 宽屏桌面：加宽英雄区，指标四列。
  wide,
}

/// 天气详情弹窗的响应式度量。
///
/// 入参是程序窗口可用视口；输出保证 dialog 宽高不超过扣除边距后的
/// 可用区域，并随窗口缩放连续调整字号与密度，避免弹窗大于页面。
@immutable
class WeatherDetailLayoutMetrics {
  const WeatherDetailLayoutMetrics({
    required this.mode,
    required this.dialogWidth,
    required this.dialogHeight,
    required this.insetPadding,
    required this.contentPadding,
    required this.useTwoColumn,
    required this.heroFlex,
    required this.sideFlex,
    required this.gridColumns,
    required this.sectionGap,
    required this.cardPadding,
    required this.heroPanelPadding,
    required this.tempFontSize,
    required this.closeButtonSize,
    required this.cornerRadius,
    required this.compactHeight,
    required this.heroMinHeight,
    required this.metricCellHeight,
  });

  /// [viewport] 为窗口/视口逻辑尺寸，不是扣除 inset 后的尺寸。
  factory WeatherDetailLayoutMetrics.resolve(Size viewport) {
    final width =
        viewport.width.isFinite && viewport.width > 0 ? viewport.width : 390.0;
    final height =
        viewport.height.isFinite && viewport.height > 0
            ? viewport.height
            : 844.0;

    final mode = _resolveMode(width);
    final compactHeight = height < 720;
    final veryShort = height < 560;
    final tightWindow = width < 360 || height < 480;

    // 边距随窗口收缩，且不得超过视口的一定比例，避免小窗口被边距挤爆。
    final baseHInset = switch (mode) {
      WeatherDetailLayoutMode.mobile => 8.0,
      WeatherDetailLayoutMode.tablet => 16.0,
      WeatherDetailLayoutMode.desktop => 20.0,
      WeatherDetailLayoutMode.wide => 24.0,
    };
    final baseVInset = switch (mode) {
      WeatherDetailLayoutMode.mobile => 8.0,
      WeatherDetailLayoutMode.tablet => 12.0,
      WeatherDetailLayoutMode.desktop => 16.0,
      WeatherDetailLayoutMode.wide => 20.0,
    };
    final horizontalInset = math.min(baseHInset, width * 0.06);
    final verticalInset = math.min(baseVInset, height * 0.05);

    // 可用区：禁止用 max 把尺寸抬到超过真实窗口。
    final availableWidth = math.max(240.0, width - horizontalInset * 2);
    final availableHeight = math.max(240.0, height - verticalInset * 2);
    // 再次与真实视口硬夹紧（极端小窗口时 available 可能仍大于视口）。
    final safeWidth = math.min(availableWidth, width);
    final safeHeight = math.min(availableHeight, height);

    // 目标尺寸：宽用档位上限，高用档位上限与可用高度比例共同约束。
    final targetWidth = switch (mode) {
      WeatherDetailLayoutMode.mobile => safeWidth,
      WeatherDetailLayoutMode.tablet => math.min(720.0, safeWidth),
      WeatherDetailLayoutMode.desktop => math.min(960.0, safeWidth),
      WeatherDetailLayoutMode.wide => math.min(1200.0, safeWidth),
    };
    final heightCap = switch (mode) {
      WeatherDetailLayoutMode.mobile => safeHeight,
      WeatherDetailLayoutMode.tablet => math.min(840.0, safeHeight * 0.96),
      WeatherDetailLayoutMode.desktop => math.min(860.0, safeHeight * 0.94),
      WeatherDetailLayoutMode.wide => math.min(880.0, safeHeight * 0.92),
    };
    final targetHeight = math.min(heightCap, safeHeight);

    // 最终尺寸：永远不超过可用区。
    final dialogWidth = math.min(targetWidth, safeWidth);
    final dialogHeight = math.min(targetHeight, safeHeight);

    final useTwoColumn =
        mode != WeatherDetailLayoutMode.mobile &&
        dialogWidth >= 680 &&
        dialogHeight >= 420 &&
        !veryShort;

    final gridColumns = switch (mode) {
      WeatherDetailLayoutMode.mobile => dialogWidth >= 340 ? 2 : 1,
      WeatherDetailLayoutMode.tablet => dialogWidth >= 640 ? 3 : 2,
      WeatherDetailLayoutMode.desktop => 3,
      WeatherDetailLayoutMode.wide => 4,
    };

    final sectionGap = switch ((tightWindow, compactHeight, mode)) {
      (true, _, _) => 8.0,
      (false, true, _) => 10.0,
      (false, false, WeatherDetailLayoutMode.mobile) => 12.0,
      (false, false, _) => 14.0,
    };

    final padH = (mode == WeatherDetailLayoutMode.mobile ? 14.0 : 20.0).clamp(
      10.0,
      dialogWidth * 0.06,
    );
    final padTop = (compactHeight ? 12.0 : 16.0).clamp(
      8.0,
      dialogHeight * 0.04,
    );
    final padBottom = (compactHeight ? 14.0 : 18.0).clamp(
      10.0,
      dialogHeight * 0.04,
    );
    final contentPadding = EdgeInsets.fromLTRB(padH, padTop, padH, padBottom);

    final cardPadding =
        compactHeight || tightWindow
            ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
            : const EdgeInsets.symmetric(horizontal: 14, vertical: 12);

    final heroPanelPadding =
        compactHeight
            ? const EdgeInsets.symmetric(horizontal: 16, vertical: 14)
            : const EdgeInsets.symmetric(horizontal: 20, vertical: 20);

    // 温度字号随窗口短边连续缩放，而不是只靠档位跳变。
    final shortSide = math.min(dialogWidth, dialogHeight);
    final tempFontRaw = (shortSide * (useTwoColumn ? 0.14 : 0.16)).clamp(
      44.0,
      92.0,
    );
    final tempFontSize =
        compactHeight ? math.min(tempFontRaw, 64.0) : tempFontRaw;

    final closeButtonSize =
        tightWindow
            ? 32.0
            : (mode == WeatherDetailLayoutMode.mobile ? 36.0 : 40.0);
    final cornerRadius = mode == WeatherDetailLayoutMode.mobile ? 16.0 : 12.0;
    final heroMinHeight =
        useTwoColumn
            ? math.min(compactHeight ? 160.0 : 200.0, dialogHeight * 0.35)
            : 0.0;
    final metricCellHeight = (compactHeight || tightWindow) ? 54.0 : 62.0;

    return WeatherDetailLayoutMetrics(
      mode: mode,
      dialogWidth: dialogWidth,
      dialogHeight: dialogHeight,
      insetPadding: EdgeInsets.symmetric(
        horizontal: horizontalInset,
        vertical: verticalInset,
      ),
      contentPadding: contentPadding,
      useTwoColumn: useTwoColumn,
      heroFlex: mode == WeatherDetailLayoutMode.wide ? 5 : 4,
      sideFlex: mode == WeatherDetailLayoutMode.wide ? 7 : 6,
      gridColumns: gridColumns,
      sectionGap: sectionGap,
      cardPadding: cardPadding,
      heroPanelPadding: heroPanelPadding,
      tempFontSize: tempFontSize,
      closeButtonSize: closeButtonSize,
      cornerRadius: cornerRadius,
      compactHeight: compactHeight,
      heroMinHeight: heroMinHeight,
      metricCellHeight: metricCellHeight,
    );
  }

  static WeatherDetailLayoutMode _resolveMode(double width) {
    if (ResponsiveBreakpoints.isMobile(width)) {
      return WeatherDetailLayoutMode.mobile;
    }
    if (ResponsiveBreakpoints.isTablet(width)) {
      return WeatherDetailLayoutMode.tablet;
    }
    if (ResponsiveBreakpoints.isWide(width)) {
      return WeatherDetailLayoutMode.wide;
    }
    return WeatherDetailLayoutMode.desktop;
  }

  final WeatherDetailLayoutMode mode;
  final double dialogWidth;
  final double dialogHeight;
  final EdgeInsets insetPadding;
  final EdgeInsets contentPadding;
  final bool useTwoColumn;
  final int heroFlex;
  final int sideFlex;
  final int gridColumns;
  final double sectionGap;
  final EdgeInsets cardPadding;
  final EdgeInsets heroPanelPadding;
  final double tempFontSize;
  final double closeButtonSize;
  final double cornerRadius;
  final bool compactHeight;
  final double heroMinHeight;
  final double metricCellHeight;

  bool get isMobile => mode == WeatherDetailLayoutMode.mobile;

  /// 温度字号应用系统文字缩放，并限制在窗口可读范围内。
  double scaledTempSize(TextScaler scaler) {
    final scaled = scaler.scale(tempFontSize);
    return scaled.clamp(36.0, tempFontSize * 1.3);
  }
}
