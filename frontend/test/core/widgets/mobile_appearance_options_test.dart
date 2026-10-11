// 样例 `.appearance-options` 的几何与配色守卫：等分三列、末行留空、
// 按钮 min-height 36，选中项走 actionFill 一族。
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:omninest/core/widgets/mobile_appearance_options.dart';

void main() {
  Future<void> pumpOptions(
    WidgetTester tester,
    List<String> values,
    String selected, {
    ValueChanged<String>? onSelected,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: MobileAppearanceOptions<String>(
                values: values,
                selected: selected,
                semanticLabel: '字号',
                labelBuilder: (value) => value,
                onSelected: onSelected ?? (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Size boxOf(WidgetTester tester, String label) {
    return tester.getSize(
      find.ancestor(
        of: find.text(label),
        matching: find.byType(AnimatedContainer),
      ),
    );
  }

  double leftOf(WidgetTester tester, String label) {
    return tester
        .getTopLeft(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(AnimatedContainer),
          ),
        )
        .dx;
  }

  Color fillOf(WidgetTester tester, String label) {
    return (tester
                .widget<AnimatedContainer>(
                  find.ancestor(
                    of: find.text(label),
                    matching: find.byType(AnimatedContainer),
                  ),
                )
                .decoration!
            as BoxDecoration)
        .color!;
  }

  testWidgets('三列等分：五档排两行，末行空位不拉伸', (tester) async {
    await pumpOptions(tester, const ['a', 'b', 'c', 'd', 'e'], 'c');

    final widths = [
      for (final label in const ['a', 'b', 'c', 'd', 'e'])
        boxOf(tester, label).width,
    ];
    expect(widths.toSet().length, 1, reason: '样例是 repeat(3,1fr)，五档必须同宽而不是两档拉满');
    expect(
      leftOf(tester, 'd'),
      closeTo(leftOf(tester, 'a'), 0.01),
      reason: '第二行首格要与第一行首格同列',
    );
    expect(
      leftOf(tester, 'e'),
      closeTo(leftOf(tester, 'b'), 0.01),
      reason: '第二行次格要与第一行次格同列',
    );
    // 容器 300 - 内衬 8 - 两道 4 间隙 = 284，三列各 94.67。描边走
    // StrokeAlign.inside，不占布局，所以不按 CSS 再减 2。
    expect(widths.first, closeTo(284 / 3, 0.01));
  });

  testWidgets('按钮高 36 且选中态取 actionFill 一族', (tester) async {
    await pumpOptions(tester, const ['x', 'y', 'z'], 'y');

    expect(boxOf(tester, 'y').height, 36);
    expect(fillOf(tester, 'y'), MobileEnvPalette.dark.actionFill);
    expect(fillOf(tester, 'x'), Colors.transparent);

    final ink =
        tester.renderObject<RenderParagraph>(find.text('x')).text.style!.color!;
    expect(ink, MobileEnvPalette.dark.appearanceOptionInk);
  });

  testWidgets('点未选中项把该值回传，选中项本身也可点', (tester) async {
    final tapped = <String>[];
    await pumpOptions(
      tester,
      const ['a', 'b', 'c'],
      'b',
      onSelected: tapped.add,
    );

    await tester.tap(find.text('c'));
    await tester.tap(find.text('a'));
    await tester.tap(find.text('b'));
    await tester.pumpAndSettle();

    expect(tapped, ['c', 'a', 'b'], reason: '任何一格都必须可点并回传自身值，重选当前项不能被吞掉');
  });

  testWidgets('读屏按样例的 aria-checked 播报，不出现 selected 与 checked 双标', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpOptions(tester, const ['a', 'b', 'c'], 'b');

    final selectedNode = tester.getSemantics(find.text('b')).toString();
    final plainNode = tester.getSemantics(find.text('a')).toString();

    // 样例这一组是 role="radio" + aria-checked，不是 tab 的选中态。
    // selected 与 checked 同时置位会让读屏把"已选择/已勾选"播两遍。
    expect(selectedNode, contains('hasCheckedState'));
    expect(selectedNode, contains('isChecked'));
    expect(selectedNode, contains('isInMutuallyExclusiveGroup'));
    expect(selectedNode, isNot(contains('isSelected')));
    expect(plainNode, isNot(contains('isChecked')));
    expect(plainNode, isNot(contains('isSelected')));
    // 名称只播一次：Semantics 与子级 Text 都写 label 时，合并结果是 "b\nb"。
    expect(selectedNode, contains('label: "b"'));
    expect(selectedNode, isNot(contains(r'b\nb')));
    expect(tester.takeException(), isNull);
    handle.dispose();
  });
}
