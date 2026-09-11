import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/portal/presentation/widgets/portal_desktop_visual_shells.dart';

void main() {
  group('resolvePortalDesktopLayoutTier', () {
    test('1120 及以上进入三栏宽布局（平板与桌面共用）', () {
      expect(
        resolvePortalDesktopLayoutTier(1120),
        PortalDesktopLayoutTier.wide,
      );
      expect(
        resolvePortalDesktopLayoutTier(1936),
        PortalDesktopLayoutTier.wide,
      );
    });

    test('900-1119 进入两栏中间档，覆盖最小桌面宽度', () {
      // 桌面最小窗 1024 减去壳层左右 32 内边距后的内容区宽度。
      expect(
        resolvePortalDesktopLayoutTier(960),
        PortalDesktopLayoutTier.twoColumn,
      );
      expect(
        resolvePortalDesktopLayoutTier(1119),
        PortalDesktopLayoutTier.twoColumn,
      );
    });

    test('900 以下回落单栏兜底', () {
      expect(
        resolvePortalDesktopLayoutTier(899),
        PortalDesktopLayoutTier.singleColumn,
      );
      expect(
        resolvePortalDesktopLayoutTier(600),
        PortalDesktopLayoutTier.singleColumn,
      );
    });
  });
}
