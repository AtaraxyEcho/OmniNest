import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/widgets/responsive_breakpoints.dart';
import 'package:omninest/features/portal/presentation/widgets/weather_detail_layout.dart';

void main() {
  group('WeatherDetailLayoutMetrics.resolve', () {
    test('手机宽度使用移动档位且不超视口', () {
      final metrics = WeatherDetailLayoutMetrics.resolve(const Size(390, 844));
      expect(metrics.mode, WeatherDetailLayoutMode.mobile);
      expect(metrics.isMobile, isTrue);
      expect(metrics.gridColumns, 2);
      expect(metrics.useTwoColumn, isFalse);
      expect(metrics.dialogWidth, lessThanOrEqualTo(390));
      expect(metrics.dialogHeight, lessThanOrEqualTo(844));
      expect(metrics.cornerRadius, 16);
    });

    test('平板宽度使用平板档位与双栏', () {
      final metrics = WeatherDetailLayoutMetrics.resolve(const Size(820, 1180));
      expect(metrics.mode, WeatherDetailLayoutMode.tablet);
      expect(metrics.gridColumns, 3);
      expect(metrics.useTwoColumn, isTrue);
      expect(metrics.dialogWidth, lessThanOrEqualTo(820));
      expect(metrics.dialogWidth, lessThanOrEqualTo(720));
    });

    test('窄平板竖屏回退单列', () {
      final metrics = WeatherDetailLayoutMetrics.resolve(const Size(620, 900));
      expect(metrics.mode, WeatherDetailLayoutMode.tablet);
      expect(metrics.useTwoColumn, isFalse);
    });

    test('桌面宽度使用桌面档位', () {
      final metrics = WeatherDetailLayoutMetrics.resolve(const Size(1100, 900));
      expect(metrics.mode, WeatherDetailLayoutMode.desktop);
      expect(metrics.useTwoColumn, isTrue);
      expect(metrics.gridColumns, 3);
      expect(metrics.dialogWidth, lessThanOrEqualTo(960));
      expect(metrics.dialogWidth, lessThanOrEqualTo(1100));
    });

    test('宽屏使用四列指标', () {
      final metrics = WeatherDetailLayoutMetrics.resolve(
        const Size(1920, 1080),
      );
      expect(metrics.mode, WeatherDetailLayoutMode.wide);
      expect(metrics.gridColumns, 4);
      expect(metrics.dialogWidth, lessThanOrEqualTo(1200));
      expect(metrics.dialogWidth, greaterThan(900));
      expect(metrics.dialogWidth, lessThanOrEqualTo(1920));
      expect(metrics.dialogHeight, lessThanOrEqualTo(1080));
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
        Size(1366, 768),
        Size(1440, 900),
        Size(1920, 1080),
        Size(2560, 1440),
        Size(480, 320),
        Size(900, 500),
      ];
      for (final size in sizes) {
        final metrics = WeatherDetailLayoutMetrics.resolve(size);
        expect(
          metrics.dialogWidth + metrics.insetPadding.horizontal,
          lessThanOrEqualTo(size.width + 0.01),
          reason: 'width overflow at $size',
        );
        expect(
          metrics.dialogHeight + metrics.insetPadding.vertical,
          lessThanOrEqualTo(size.height + 0.01),
          reason: 'height overflow at $size',
        );
        expect(
          metrics.dialogWidth,
          lessThanOrEqualTo(size.width),
          reason: 'dialog width at $size',
        );
        expect(
          metrics.dialogHeight,
          lessThanOrEqualTo(size.height),
          reason: 'dialog height at $size',
        );
      }
    });

    test('矮窗口压缩间距并可能关闭双栏', () {
      final shortDesktop = WeatherDetailLayoutMetrics.resolve(
        const Size(1440, 520),
      );
      expect(shortDesktop.compactHeight, isTrue);
      expect(shortDesktop.useTwoColumn, isFalse);
      expect(shortDesktop.dialogHeight, lessThanOrEqualTo(520));

      final landscapePhone = WeatherDetailLayoutMetrics.resolve(
        const Size(844, 390),
      );
      expect(landscapePhone.compactHeight, isTrue);
      expect(landscapePhone.dialogHeight, lessThanOrEqualTo(390));
    });

    test('断点与全局 ResponsiveBreakpoints 一致', () {
      const mobileEdge = Size(ResponsiveBreakpoints.mobile - 1, 800);
      const tabletEdge = Size(ResponsiveBreakpoints.desktop - 1, 800);
      const desktopEdge = Size(ResponsiveBreakpoints.desktop, 800);
      const wideEdge = Size(ResponsiveBreakpoints.wide, 800);

      expect(
        WeatherDetailLayoutMetrics.resolve(mobileEdge).mode,
        WeatherDetailLayoutMode.mobile,
      );
      expect(
        WeatherDetailLayoutMetrics.resolve(tabletEdge).mode,
        WeatherDetailLayoutMode.tablet,
      );
      expect(
        WeatherDetailLayoutMetrics.resolve(desktopEdge).mode,
        WeatherDetailLayoutMode.desktop,
      );
      expect(
        WeatherDetailLayoutMetrics.resolve(wideEdge).mode,
        WeatherDetailLayoutMode.wide,
      );
    });

    test('温度字号随窗口连续缩放并有上限', () {
      final small = WeatherDetailLayoutMetrics.resolve(const Size(390, 700));
      final large = WeatherDetailLayoutMetrics.resolve(const Size(1920, 1080));
      expect(small.tempFontSize, lessThanOrEqualTo(large.tempFontSize + 0.01));
      final normal = large.scaledTempSize(TextScaler.noScaling);
      final scaled = large.scaledTempSize(const TextScaler.linear(1.4));
      expect(normal, closeTo(large.tempFontSize, 0.01));
      expect(scaled, lessThanOrEqualTo(large.tempFontSize * 1.3 + 0.01));
    });
  });
}
