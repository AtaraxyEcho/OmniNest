import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/route/app_route_surface.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop_policy.dart';

void main() {
  group('routeBackdropPolicy', () {
    test('移动壳层：媒体路由 ambient、阅读 focus、其余 utility', () {
      expect(
        routeBackdropPolicy('/photos/albums/1', mobileShell: true),
        AppBackdropPolicy.ambientMedia,
      );
      expect(
        routeBackdropPolicy('/video/xyz/play', mobileShell: true),
        AppBackdropPolicy.ambientMedia,
      );
      expect(
        routeBackdropPolicy('/music/history', mobileShell: true),
        AppBackdropPolicy.ambientMedia,
      );
      expect(
        routeBackdropPolicy('/reader/items/9/chapters/1', mobileShell: true),
        AppBackdropPolicy.focusReading,
      );
      expect(
        routeBackdropPolicy('/profile', mobileShell: true),
        AppBackdropPolicy.utilitySurface,
      );
      expect(
        routeBackdropPolicy('/notifications', mobileShell: true),
        AppBackdropPolicy.utilitySurface,
      );
    });

    test('桌面端保持原有语义：照片/阅读静态快照、影视与系统实底', () {
      expect(
        routeBackdropPolicy('/photos/albums/1', mobileShell: false),
        AppBackdropPolicy.staticContent,
      );
      expect(
        routeBackdropPolicy('/reader/items/9', mobileShell: false),
        AppBackdropPolicy.staticContent,
      );
      expect(
        routeBackdropPolicy('/video/xyz', mobileShell: false),
        AppBackdropPolicy.work,
      );
      expect(
        routeBackdropPolicy('/music/history', mobileShell: false),
        AppBackdropPolicy.work,
      );
      expect(
        routeBackdropPolicy('/profile', mobileShell: false),
        AppBackdropPolicy.work,
      );
    });

    test('环境模式呈现阶梯随档位单调递减', () {
      final immersive = AppEnvironmentPresentation.of(
        AppEnvironmentMode.immersive,
      );
      final ambient = AppEnvironmentPresentation.of(AppEnvironmentMode.ambient);
      final focus = AppEnvironmentPresentation.of(AppEnvironmentMode.focus);
      final utility = AppEnvironmentPresentation.of(AppEnvironmentMode.utility);
      expect(immersive.wallpaperOpacity, 1);
      expect(ambient.wallpaperOpacity, lessThan(immersive.wallpaperOpacity));
      expect(focus.wallpaperOpacity, lessThan(ambient.wallpaperOpacity));
      expect(utility.wallpaperOpacity, lessThan(focus.wallpaperOpacity));
      expect(ambient.blurSigma, greaterThan(0));
      expect(focus.blurSigma, greaterThan(ambient.blurSigma));
    });

    test('四空间分支策略全部可见且共享同一壁纸身份', () {
      for (final policy in const <AppBackdropPolicy>[
        AppBackdropPolicy.portalMobile,
        AppBackdropPolicy.ambientMedia,
        AppBackdropPolicy.focusReading,
        AppBackdropPolicy.utilitySurface,
      ]) {
        expect(policy.visible, isTrue);
      }
      expect(
        AppBackdropPolicy.portalMobile.environmentMode,
        AppEnvironmentMode.immersive,
      );
      expect(
        AppBackdropPolicy.ambientMedia.environmentMode,
        AppEnvironmentMode.ambient,
      );
      expect(
        AppBackdropPolicy.focusReading.environmentMode,
        AppEnvironmentMode.focus,
      );
      expect(
        AppBackdropPolicy.utilitySurface.environmentMode,
        AppEnvironmentMode.utility,
      );
    });
  });
}
