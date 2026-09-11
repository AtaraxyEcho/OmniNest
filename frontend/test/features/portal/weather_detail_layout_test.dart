import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/widgets/responsive_breakpoints.dart';
import 'package:omninest/features/portal/presentation/widgets/weather_detail_layout.dart';

void main() {
  group('WeatherDetailLayoutMetrics.resolve', () {
    test('手机使用单列且不超视口', () {
      final metrics = WeatherDetailLayoutMetrics.resolve(const Size(390, 844));
      expect(metrics.mode, WeatherDetailLayoutMode.mobile);
      expect(metrics.useHeroSplit, isFalse);
      expect(metrics.metricColumns, 2);
      expect(metrics.dialogWidth, lessThanOrEqualTo(390));
      expect(metrics.dialogWidth, lessThanOrEqualTo(kWeatherDetailMaxWidth));
    });

    test('平板使用英雄双列与三列指标', () {
      final metrics = WeatherDetailLayoutMetrics.resolve(const Size(820, 1180));
      expect(metrics.mode, WeatherDetailLayoutMode.tablet);
      expect(metrics.useHeroSplit, isTrue);
      expect(metrics.metricColumns, 3);
      expect(metrics.dialogWidth, lessThanOrEqualTo(kWeatherDetailMaxWidth));
    });

    test('桌面宽度不超过 max-w-3xl', () {
      final metrics = WeatherDetailLayoutMetrics.resolve(
        const Size(1600, 1000),
      );
      expect(metrics.mode, WeatherDetailLayoutMode.desktop);
      expect(metrics.dialogWidth, kWeatherDetailMaxWidth);
      expect(metrics.dialogHeight, lessThanOrEqualTo(1000));
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
        Size(2560, 1440),
        Size(480, 320),
      ];
      for (final size in sizes) {
        final metrics = WeatherDetailLayoutMetrics.resolve(size);
        expect(
          metrics.dialogWidth,
          lessThanOrEqualTo(size.width),
          reason: 'width at $size',
        );
        expect(
          metrics.dialogHeight,
          lessThanOrEqualTo(size.height),
          reason: 'height at $size',
        );
        expect(
          metrics.dialogWidth + metrics.insetPadding.horizontal,
          lessThanOrEqualTo(size.width + 0.01),
          reason: 'width+inset at $size',
        );
        expect(
          metrics.dialogHeight + metrics.insetPadding.vertical,
          lessThanOrEqualTo(size.height + 0.01),
          reason: 'height+inset at $size',
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

    test('温度字号有上下限', () {
      final small = WeatherDetailLayoutMetrics.resolve(const Size(360, 640));
      final large = WeatherDetailLayoutMetrics.resolve(const Size(1920, 1080));
      expect(small.tempFontSize, greaterThanOrEqualTo(48));
      expect(large.tempFontSize, lessThanOrEqualTo(88));
      final scaled = large.scaledTempSize(const TextScaler.linear(1.4));
      expect(scaled, lessThanOrEqualTo(large.tempFontSize * 1.25 + 0.01));
    });
  });
}
