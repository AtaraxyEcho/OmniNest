import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/widgets/responsive_breakpoints.dart';
import 'package:omninest/features/portal/presentation/widgets/weather_detail_layout.dart';

void main() {
  group('WeatherDetailLayoutMetrics.resolve', () {
    test('手机单列，宽度贴边且不超视口', () {
      final metrics = WeatherDetailLayoutMetrics.resolve(const Size(390, 844));
      expect(metrics.mode, WeatherDetailLayoutMode.mobile);
      expect(metrics.useHeroSplit, isFalse);
      expect(metrics.dialogWidth, lessThanOrEqualTo(390));
      expect(metrics.dialogWidth, lessThanOrEqualTo(kWeatherDetailMaxWidth));
    });

    test('平板/桌面英雄区等宽双列', () {
      final tablet = WeatherDetailLayoutMetrics.resolve(const Size(820, 1180));
      expect(tablet.useHeroSplit, isTrue);
      expect(tablet.metricColumns, 3);
      expect(tablet.sectionGap, 16);

      final desktop = WeatherDetailLayoutMetrics.resolve(
        const Size(1600, 1000),
      );
      expect(desktop.mode, WeatherDetailLayoutMode.desktop);
      expect(desktop.dialogWidth, kWeatherDetailMaxWidth);
      expect(desktop.useHeroSplit, isTrue);
      // 左卡与右侧两卡总高对齐：split*2 + gap ≈ hero
      final gap = desktop.sectionGap * 0.75;
      expect(
        desktop.splitCardHeight * 2 + gap,
        closeTo(desktop.heroHeight, 1.0),
      );
      expect(
        desktop.heroHeight,
        greaterThanOrEqualTo(kWeatherDetailHeroMinHeight),
      );
    });

    test('温度字号落在样例 4rem–6rem 区间附近', () {
      final small = WeatherDetailLayoutMetrics.resolve(const Size(360, 700));
      final large = WeatherDetailLayoutMetrics.resolve(const Size(1920, 1080));
      expect(small.tempFontSize, greaterThanOrEqualTo(64));
      expect(large.tempFontSize, lessThanOrEqualTo(96));
    });

    test('弹窗尺寸永不超出程序窗口', () {
      const sizes = <Size>[
        Size(320, 480),
        Size(360, 640),
        Size(390, 844),
        Size(600, 800),
        Size(800, 600),
        Size(1024, 768),
        Size(1280, 720),
        Size(1440, 900),
        Size(1920, 1080),
        Size(480, 320),
      ];
      for (final size in sizes) {
        final metrics = WeatherDetailLayoutMetrics.resolve(size);
        expect(metrics.dialogWidth, lessThanOrEqualTo(size.width));
        expect(metrics.dialogHeight, lessThanOrEqualTo(size.height));
        expect(
          metrics.dialogWidth + metrics.insetPadding.horizontal,
          lessThanOrEqualTo(size.width + 0.01),
        );
        expect(
          metrics.dialogHeight + metrics.insetPadding.vertical,
          lessThanOrEqualTo(size.height + 0.01),
        );
      }
    });

    test('矮窗口关闭英雄双列', () {
      final short = WeatherDetailLayoutMetrics.resolve(const Size(1440, 520));
      expect(short.compactHeight, isTrue);
      expect(short.useHeroSplit, isFalse);
    });

    test('断点与 ResponsiveBreakpoints 一致', () {
      expect(
        WeatherDetailLayoutMetrics.resolve(
          const Size(ResponsiveBreakpoints.mobile - 1, 800),
        ).mode,
        WeatherDetailLayoutMode.mobile,
      );
      expect(
        WeatherDetailLayoutMetrics.resolve(
          const Size(ResponsiveBreakpoints.desktop - 1, 800),
        ).mode,
        WeatherDetailLayoutMode.tablet,
      );
      expect(
        WeatherDetailLayoutMetrics.resolve(
          const Size(ResponsiveBreakpoints.desktop, 800),
        ).mode,
        WeatherDetailLayoutMode.desktop,
      );
    });
  });
}
