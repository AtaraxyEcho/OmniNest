import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_redesign_components.dart';

void main() {
  Future<void> pumpEntrance(
    WidgetTester tester, {
    required bool reduceMotion,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: const Scaffold(
            body: AdminSectionEntrance(children: [Text('概览面板'), Text('任务面板')]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 只看入场容器内部：MaterialApp 的路由过渡自带 FadeTransition/SlideTransition，
  /// 不限定作用域会把路由动画一起算进来。
  List<FadeTransition> entranceFades(WidgetTester tester) =>
      tester
          .widgetList<FadeTransition>(
            find.descendant(
              of: find.byType(AdminSectionEntrance),
              matching: find.byType(FadeTransition),
            ),
          )
          .cast<FadeTransition>()
          .toList();

  List<SlideTransition> entranceSlides(WidgetTester tester) =>
      tester
          .widgetList<SlideTransition>(
            find.descendant(
              of: find.byType(AdminSectionEntrance),
              matching: find.byType(SlideTransition),
            ),
          )
          .cast<SlideTransition>()
          .toList();

  testWidgets('减少动态效果时入场动画直接落到终态，内容不得隐身', (tester) async {
    await pumpEntrance(tester, reduceMotion: true);

    final fades = entranceFades(tester);
    expect(fades, hasLength(2));
    for (final fade in fades) {
      expect(fade.opacity.value, 1.0, reason: '透明度停在起点等于整块面板不可见');
    }
    for (final slide in entranceSlides(tester)) {
      expect(slide.position.value, Offset.zero);
    }
  });

  testWidgets('未要求减少动效时入场动画照常播放到终态', (tester) async {
    await pumpEntrance(tester, reduceMotion: false);

    final fades = entranceFades(tester);
    expect(fades, hasLength(2));
    expect(fades.every((fade) => fade.opacity.value == 1.0), isTrue);
  });
}
