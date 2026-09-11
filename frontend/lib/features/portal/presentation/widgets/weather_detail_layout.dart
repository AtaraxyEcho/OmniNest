import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:omninest/core/widgets/responsive_breakpoints.dart';

/// 天气详情弹窗布局档位。
enum WeatherDetailLayoutMode {
  /// 手机：单列紧凑，宽度贴边。
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
/// 依据视口宽高在手机 / 平板 / 桌面 / 宽屏之间切换布局，并在矮窗口下压缩
/// 间距与字号，保证 Win / macOS / Web 桌面与移动端窗口缩放时仍可读可点。
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
  });

  factory WeatherDetailLayoutMetrics.resolve(Size viewport) {
    final width = viewport.width;
    final height = viewport.height;

    final mode = _resolveMode(width);
    final compactHeight = height < 720;
    final veryShort = height < 560;

    final horizontalInset = switch (mode) {
      WeatherDetailLayoutMode.mobile => 8.0,
      WeatherDetailLayoutMode.tablet => 20.0,
      WeatherDetailLayoutMode.desktop => 28.0,
      WeatherDetailLayoutMode.wide => 32.0,
    };
    final verticalInset = switch (mode) {
      WeatherDetailLayoutMode.mobile => 10.0,
      WeatherDetailLayoutMode.tablet => 18.0,
      WeatherDetailLayoutMode.desktop => 24.0,
      WeatherDetailLayoutMode.wide => 28.0,
    };

    final availableWidth = math.max(280.0, width - horizontalInset * 2);
    final availableHeight = math.max(320.0, height - verticalInset * 2);

    final maxWidth = switch (mode) {
      WeatherDetailLayoutMode.mobile => availableWidth,
      WeatherDetailLayoutMode.tablet => 720.0,
      WeatherDetailLayoutMode.desktop => 980.0,
      WeatherDetailLayoutMode.wide => 1280.0,
    };
    final maxHeight = switch (mode) {
      WeatherDetailLayoutMode.mobile => availableHeight,
      WeatherDetailLayoutMode.tablet => math.min(820.0, availableHeight),
      WeatherDetailLayoutMode.desktop => math.min(860.0, availableHeight),
      WeatherDetailLayoutMode.wide => math.min(900.0, availableHeight),
    };

    final dialogWidth = math.min(maxWidth, availableWidth);
    final dialogHeight = math.min(maxHeight, availableHeight);

    // 窄平板竖屏或矮窗口改为单列，避免侧栏被压成竖条。
    final useTwoColumn =
        mode != WeatherDetailLayoutMode.mobile &&
        dialogWidth >= 640 &&
        !veryShort;

    final gridColumns = switch (mode) {
      WeatherDetailLayoutMode.mobile => 2,
      WeatherDetailLayoutMode.tablet => dialogWidth >= 640 ? 3 : 2,
      WeatherDetailLayoutMode.desktop => 3,
      WeatherDetailLayoutMode.wide => 4,
    };

    final sectionGap = switch ((compactHeight, mode)) {
      (true, _) => 10.0,
      (false, WeatherDetailLayoutMode.mobile) => 14.0,
      (false, _) => 16.0,
    };

    final contentPadding = EdgeInsets.fromLTRB(
      mode == WeatherDetailLayoutMode.mobile ? 16 : 24,
      compactHeight ? 12 : (mode == WeatherDetailLayoutMode.mobile ? 14 : 20),
      mode == WeatherDetailLayoutMode.mobile ? 16 : 24,
      compactHeight ? 16 : 22,
    );

    final cardPadding =
        compactHeight
            ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
            : const EdgeInsets.symmetric(horizontal: 14, vertical: 12);

    final heroPanelPadding =
        compactHeight
            ? const EdgeInsets.symmetric(horizontal: 18, vertical: 16)
            : const EdgeInsets.symmetric(horizontal: 24, vertical: 24);

    final tempFontSize = switch (mode) {
      WeatherDetailLayoutMode.mobile => compactHeight ? 52.0 : 60.0,
      WeatherDetailLayoutMode.tablet => compactHeight ? 56.0 : 68.0,
      WeatherDetailLayoutMode.desktop => compactHeight ? 64.0 : 80.0,
      WeatherDetailLayoutMode.wide => compactHeight ? 72.0 : 92.0,
    };

    final closeButtonSize =
        mode == WeatherDetailLayoutMode.mobile ? 36.0 : 40.0;
    final cornerRadius = mode == WeatherDetailLayoutMode.mobile ? 16.0 : 12.0;
    final heroMinHeight = useTwoColumn ? (compactHeight ? 180.0 : 220.0) : 0.0;

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

  bool get isMobile => mode == WeatherDetailLayoutMode.mobile;

  /// 指标单元宽高比，保证长文案不被竖向裁切。
  double get gridChildAspectRatio {
    final base = gridColumns >= 4 ? 2.6 : 2.35;
    return compactHeight ? base + 0.15 : base;
  }

  /// 温度字号应用系统文字缩放，保证无障碍缩放下不溢出。
  double scaledTempSize(TextScaler scaler) {
    final scaled = scaler.scale(tempFontSize);
    return math.min(scaled, tempFontSize * 1.35);
  }
}
