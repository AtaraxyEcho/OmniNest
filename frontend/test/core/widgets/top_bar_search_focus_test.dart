import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/widgets/top_bar_search_focus.dart';

/// 顶栏搜索 Ctrl/Cmd+F 注册表：LIFO、自检跳过与注销语义。
void main() {
  group('TopBarSearchFocusRegistry', () {
    test('后注册者优先，未命中自检的条目被跳过', () {
      final registry = TopBarSearchFocusRegistry.instance;
      final focused = <String>[];
      final first = registry.register(
        TopBarSearchFocusEntry(
          focus: () => focused.add('first'),
          isActive: () => true,
        ),
      );
      addTearDown(first.dispose);
      final second = registry.register(
        TopBarSearchFocusEntry(
          focus: () => focused.add('second'),
          isActive: () => false,
        ),
      );
      addTearDown(second.dispose);

      expect(registry.focusActiveTarget(), isTrue);
      expect(focused, ['first']);
    });

    test('两条目均活跃时聚焦最后注册者（对话框覆盖顶栏槽）', () {
      final registry = TopBarSearchFocusRegistry.instance;
      final focused = <String>[];
      final first = registry.register(
        TopBarSearchFocusEntry(
          focus: () => focused.add('top-bar'),
          isActive: () => true,
        ),
      );
      addTearDown(first.dispose);
      final second = registry.register(
        TopBarSearchFocusEntry(
          focus: () => focused.add('dialog'),
          isActive: () => true,
        ),
      );
      addTearDown(second.dispose);

      expect(registry.focusActiveTarget(), isTrue);
      expect(focused, ['dialog']);
    });

    test('没有任何条目自检通过时返回 false 放行按键', () {
      final registry = TopBarSearchFocusRegistry.instance;
      final handle = registry.register(
        TopBarSearchFocusEntry(focus: () {}, isActive: () => false),
      );
      addTearDown(handle.dispose);

      expect(registry.focusActiveTarget(), isFalse);
    });

    test('注销后不再命中，重复注销幂等', () {
      final registry = TopBarSearchFocusRegistry.instance;
      var focusedCount = 0;
      final handle = registry.register(
        TopBarSearchFocusEntry(
          focus: () => focusedCount++,
          isActive: () => true,
        ),
      );

      expect(registry.focusActiveTarget(), isTrue);
      expect(focusedCount, 1);

      handle.dispose();
      handle.dispose();
      expect(registry.focusActiveTarget(), isFalse);
      expect(focusedCount, 1);
    });
  });

  group('topBarSearchKeycapLabel', () {
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    test('Apple 平台显示 ⌘F，其余显示 Ctrl+F', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(topBarSearchKeycapLabel, '⌘F');
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(topBarSearchKeycapLabel, '⌘F');
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(topBarSearchKeycapLabel, 'Ctrl+F');
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(topBarSearchKeycapLabel, 'Ctrl+F');
    });
  });
}
