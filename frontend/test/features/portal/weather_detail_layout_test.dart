import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/widgets/responsive_breakpoints.dart';
import 'package:omninest/features/portal/presentation/widgets/weather_detail_layout.dart';

void main() {
  group('WeatherDetailLayoutMetrics.resolve', () {
    test('手机宽度使用移动档位与双列指标', () {
      final metrics = WeatherDetailLayoutMetrics.resolve(const Size(390, 844));
      expect(metrics.mode, WeatherDetailLayoutMode.mobile);
      expect(metrics.isMobile, isTrue);
      expect(metrics.gridColumns, 2);
      expect(metrics.useTwoColumn, isFalse);
      expect(metrics.dialogWidth, lessThanOrEqualTo(390));
      expect(metrics.cornerRadius, 16);
    });

    test('平板宽度使用平板档位与三列双栏', () {
      final metrics = WeatherDetailLayoutMetrics.resolve(const Size(820, 1180));
      expect(metrics.mode, WeatherDetailLayoutMode.tablet);
      expect(metrics.gridColumns, 3);
      expect(metrics.useTwoColumn, isTrue);
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
      expect(metrics.dialogWidth, lessThanOrEqualTo(980));
    });

    test('宽屏使用四列指标', () {
      final metrics = WeatherDetailLayoutMetrics.resolve(
        const Size(1920, 1080),
      );
      expect(metrics.mode, WeatherDetailLayoutMode.wide);
      expect(metrics.gridColumns, 4);
      expect(metrics.dialogWidth, lessThanOrEqualTo(1280));
      expect(metrics.dialogWidth, greaterThan(1000));
    });

    test('矮窗口压缩间距并可能关闭双栏', () {
      final shortDesktop = WeatherDetailLayoutMetrics.resolve(
        const Size(1440, 520),
      );
      expect(shortDesktop.compactHeight, isTrue);
      expect(shortDesktop.useTwoColumn, isFalse);

      final landscapePhone = WeatherDetailLayoutMetrics.resolve(
        const Size(844, 390),
      );
      expect(landscapePhone.compactHeight, isTrue);
      expect(landscapePhone.dialogHeight, lessThanOrEqualTo(390));
      expect(landscapePhone.dialogHeight, greaterThanOrEqualTo(320));
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

    test('温度字号应用系统缩放并有上限', () {
      final metrics = WeatherDetailLayoutMetrics.resolve(const Size(390, 844));
      final normal = metrics.scaledTempSize(TextScaler.noScaling);
      final scaled = metrics.scaledTempSize(const TextScaler.linear(1.4));
      expect(normal, metrics.tempFontSize);
      expect(scaled, lessThanOrEqualTo(metrics.tempFontSize * 1.35));
      expect(scaled, greaterThan(normal));
    });
  });
}
