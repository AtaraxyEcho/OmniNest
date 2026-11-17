import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/window/window_geometry_service.dart';

void main() {
  group('WindowBoundsSnapshot', () {
    test('encode 与 tryDecode 往返一致', () {
      const snapshot = WindowBoundsSnapshot(
        bounds: Rect.fromLTWH(12, 34, 1280, 800),
        maximized: true,
      );
      final decoded = WindowBoundsSnapshot.tryDecode(snapshot.encode());
      expect(decoded, isNotNull);
      expect(decoded!.bounds, snapshot.bounds);
      expect(decoded.maximized, isTrue);
    });

    test('空串与非法 JSON 返回 null 而非抛错', () {
      expect(WindowBoundsSnapshot.tryDecode(null), isNull);
      expect(WindowBoundsSnapshot.tryDecode(''), isNull);
      expect(WindowBoundsSnapshot.tryDecode('not-json'), isNull);
      expect(WindowBoundsSnapshot.tryDecode('{"x":0,"w":-5,"h":10}'), isNull);
    });
  });

  group('computeStartupGeometry', () {
    test('无记忆且工作区宽裕：默认尺寸按 0.85 收窄并居中', () {
      const workArea = Rect.fromLTWH(0, 0, 2560, 1440);
      final plan = computeStartupGeometry(visibleAreas: [workArea]);
      expect(plan.maximize, isFalse);
      expect(plan.size, const Size(1280, 800));
      expect(plan.position, const Offset((2560 - 1280) / 2, (1440 - 800) / 2));
    });

    test('小屏工作区收窄到最小尺寸以下时改为最大化', () {
      // 1366×768 物理屏 + 125% 缩放后的典型工作区。
      const workArea = Rect.fromLTWH(0, 0, 1092, 614);
      final plan = computeStartupGeometry(visibleAreas: [workArea]);
      expect(plan.maximize, isTrue);
      expect(plan.size, const Size(1024, 640));
    });

    test('中等屏幕按比例收窄且不低于最小尺寸', () {
      const workArea = Rect.fromLTWH(0, 0, 1440, 900);
      final plan = computeStartupGeometry(visibleAreas: [workArea]);
      expect(plan.maximize, isFalse);
      expect(plan.size, const Size(1224, 765));
      expect(plan.position, const Offset(108, 67.5));
    });

    test('无屏幕信息时回退默认尺寸并交给系统摆放', () {
      final plan = computeStartupGeometry();
      expect(plan.size, const Size(1280, 800));
      expect(plan.position, isNull);
      expect(plan.maximize, isFalse);
    });

    test('有记忆且位置仍在可见区域内：原样沿用', () {
      const workArea = Rect.fromLTWH(0, 0, 2560, 1440);
      const saved = WindowBoundsSnapshot(
        bounds: Rect.fromLTWH(100, 80, 1500, 900),
      );
      final plan = computeStartupGeometry(
        saved: saved,
        visibleAreas: [workArea],
      );
      expect(plan.size, const Size(1500, 900));
      expect(plan.position, const Offset(100, 80));
      expect(plan.maximize, isFalse);
    });

    test('记忆尺寸小于最小尺寸时抬升到最小尺寸', () {
      const workArea = Rect.fromLTWH(0, 0, 2560, 1440);
      const saved = WindowBoundsSnapshot(bounds: Rect.fromLTWH(0, 0, 600, 400));
      final plan = computeStartupGeometry(
        saved: saved,
        visibleAreas: [workArea],
      );
      expect(plan.size, const Size(1024, 640));
    });

    test('记忆位置不在任何可见区域内：回主屏居中', () {
      const workArea = Rect.fromLTWH(0, 0, 2560, 1440);
      const saved = WindowBoundsSnapshot(
        bounds: Rect.fromLTWH(-5000, 100, 1280, 800),
      );
      final plan = computeStartupGeometry(
        saved: saved,
        visibleAreas: [workArea],
      );
      expect(plan.position, const Offset((2560 - 1280) / 2, (1440 - 800) / 2));
    });

    test('记忆位置偏右导致窗口右缘越界：夹取回工作区内', () {
      const workArea = Rect.fromLTWH(0, 0, 1536, 845);
      const saved = WindowBoundsSnapshot(
        bounds: Rect.fromLTWH(1000, 100, 1280, 718),
      );
      final plan = computeStartupGeometry(
        saved: saved,
        visibleAreas: [workArea],
      );
      expect(plan.position, const Offset(256, 100));
    });

    test('记忆为最大化时保持最大化并抬升尺寸下限', () {
      const workArea = Rect.fromLTWH(0, 0, 2560, 1440);
      const saved = WindowBoundsSnapshot(
        bounds: Rect.fromLTWH(0, 0, 1280, 800),
        maximized: true,
      );
      final plan = computeStartupGeometry(
        saved: saved,
        visibleAreas: [workArea],
      );
      expect(plan.maximize, isTrue);
      expect(plan.size, const Size(1280, 800));
    });
  });
}
