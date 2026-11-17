import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/widgets/animated_card.dart';
import 'package:omninest/features/portal/application/portal_dashboard_providers.dart';
import 'package:omninest/features/portal/presentation/widgets/portal_visual_widgets.dart';

void main() {
  group('PortalDashboardActions', () {
    test('单个分区失败不阻断其余分区刷新', () async {
      final calls = <PortalDashboardSection>[];
      final actions = PortalDashboardActions({
        for (final section in PortalDashboardSection.values)
          section: () async {
            calls.add(section);
            if (section == PortalDashboardSection.video) {
              throw StateError('video unavailable');
            }
          },
      });

      final result = await actions.refreshAll();

      expect(calls.toSet(), PortalDashboardSection.values.toSet());
      expect(result.succeeded, isFalse);
      expect(result.failedSections, {PortalDashboardSection.video});
    });

    test('局部重试只执行目标分区', () async {
      var storageCalls = 0;
      var videoCalls = 0;
      final actions = PortalDashboardActions({
        PortalDashboardSection.storage: () async => storageCalls++,
        PortalDashboardSection.video: () async => videoCalls++,
      });

      final succeeded = await actions.retry(PortalDashboardSection.storage);

      expect(succeeded, isTrue);
      expect(storageCalls, 1);
      expect(videoCalls, 0);
    });
  });

  group('Portal motion', () {
    testWidgets('父级刷新重建不会重放入场动画', (tester) async {
      late StateSetter rebuild;
      var label = 'initial';
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return AnimatedCard(
                key: const ValueKey('stable-portal-card'),
                duration: const Duration(milliseconds: 220),
                child: Text(label),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_fadeOpacity(tester, 'stable-portal-card'), 1);

      rebuild(() => label = 'refreshed');
      await tester.pump();

      expect(find.text('refreshed'), findsOneWidget);
      expect(_fadeOpacity(tester, 'stable-portal-card'), 1);
    });

    testWidgets('减少动效时入场内容首帧可见', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AnimatedCard(
            key: ValueKey('disabled-portal-card'),
            enabled: false,
            delay: Duration(seconds: 1),
            child: Text('content'),
          ),
        ),
      );

      expect(_fadeOpacity(tester, 'disabled-portal-card'), 1);
    });
  });

  group('Portal immersive top bar', () {
    testWidgets('Tab 显示顶栏且 Shift+Tab 离开后隐藏', (tester) async {
      final beforeNode = FocusNode(debugLabel: 'before portal top bar');
      addTearDown(beforeNode.dispose);
      tester.view.physicalSize = const Size(1200, 700);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TextButton(
                  focusNode: beforeNode,
                  onPressed: () {},
                  child: const Text('before'),
                ),
                PortalImmersiveTopBarReveal(
                  immersive: true,
                  child: TextButton(
                    onPressed: () {},
                    child: const Text('search'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      beforeNode.requestFocus();
      await tester.pump();
      expect(_topBarOpacity(tester), 0);
      expect(_topBarExcludeFocus(tester).excluding, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(_topBarOpacity(tester), 1);
      expect(_topBarExcludeFocus(tester).excluding, isFalse);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(beforeNode.hasFocus, isTrue);
      expect(_topBarOpacity(tester), 0);
      expect(_topBarExcludeFocus(tester).excluding, isTrue);
    });

    testWidgets('系统减少动效时顶栏过渡时长为零', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: PortalImmersiveTopBarReveal(
              immersive: true,
              child: Text('top bar'),
            ),
          ),
        ),
      );

      final opacity = tester.widget<AnimatedOpacity>(
        find.descendant(
          of: find.byKey(const ValueKey('portal-immersive-top-bar')),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      final slide = tester.widget<AnimatedSlide>(
        find.descendant(
          of: find.byKey(const ValueKey('portal-immersive-top-bar')),
          matching: find.byType(AnimatedSlide),
        ),
      );
      expect(opacity.duration, Duration.zero);
      expect(slide.duration, Duration.zero);
    });
  });
}

double _fadeOpacity(WidgetTester tester, String cardKey) {
  final fade = find.descendant(
    of: find.byKey(ValueKey(cardKey)),
    matching: find.byType(FadeTransition),
  );
  // 入场结束后 AnimatedCard 直接返回子树，不再常驻 FadeTransition。
  if (fade.evaluate().isEmpty) {
    return 1;
  }
  return tester.widget<FadeTransition>(fade).opacity.value;
}

double _topBarOpacity(WidgetTester tester) {
  return tester
      .widget<AnimatedOpacity>(
        find.descendant(
          of: find.byKey(const ValueKey('portal-immersive-top-bar')),
          matching: find.byType(AnimatedOpacity),
        ),
      )
      .opacity;
}

ExcludeFocus _topBarExcludeFocus(WidgetTester tester) {
  return tester.widget<ExcludeFocus>(
    find.descendant(
      of: find.byKey(const ValueKey('portal-immersive-top-bar')),
      matching: find.byType(ExcludeFocus),
    ),
  );
}
