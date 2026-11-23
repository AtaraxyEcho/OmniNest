import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/desktop/desktop_dock.dart';
import 'package:omninest/app/desktop/desktop_shell_state.dart';
import 'package:omninest/app/desktop/widgets/desktop_chart_tooltip.dart';

import 'desktop_test_harness.dart';

/// 详情浮层回归：图表悬停气泡与右侧详情坞都挂在 `Overlay` / 零宽容器上，
/// 这两处历史上分别踩过 `StackParentData` 强转崩溃与收起态模糊常驻，
/// 这里用最小装配钉住行为，避免同类改动再次退化。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('图表悬停气泡反复显隐不抛 StackParentData 异常', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      var visible = false;
      late StateSetter setVisible;

      await tester.pumpWidget(
        wrapDesktop(
          StatefulBuilder(
            builder: (context, setState) {
              setVisible = setState;
              return Center(
                child: DesktopBarTipOverlay(
                  visible: visible,
                  title: 'Jan',
                  value: '1.2k',
                  child: const SizedBox(width: 48, height: 120),
                ),
              );
            },
          ),
        ),
      );
      expect(tester.takeException(), isNull);

      setVisible(() => visible = true);
      await tester.pumpAndSettle();
      expect(find.text('1.2k'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // 鼠标在多根柱子之间快速滑动：连续显隐是崩溃的原始触发路径。
      for (var i = 0; i < 5; i++) {
        setVisible(() => visible = !visible);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('1.2k'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('详情坞收起后卸载毛玻璃子树', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: wrapDesktop(const SizedBox(width: 348, child: DesktopDock())),
        ),
      );
      await tester.pump();

      expect(
        find.byType(BackdropFilter),
        findsNothing,
        reason: '收起态不应常驻 BackdropFilter(26)，否则每帧都在做 GPU 模糊合成。',
      );

      container
          .read(desktopShellProvider.notifier)
          .showDetail(
            const DesktopDetailData(
              id: 'film:test',
              kind: 'film',
              title: 'Dune',
              subtitle: '2021',
              factsLabel: 'Media',
              facts: [MapEntry('Year', '2021')],
            ),
          );
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsWidgets);
      expect(find.text('Dune'), findsOneWidget);

      container.read(desktopShellProvider.notifier).setDock(false);
      await tester.pumpAndSettle();
      expect(
        find.byType(BackdropFilter),
        findsNothing,
        reason: '收起动画结束后必须卸载内部模糊，避免隐藏态继续参与合成。',
      );
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
