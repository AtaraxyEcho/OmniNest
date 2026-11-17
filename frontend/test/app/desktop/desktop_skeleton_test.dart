import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/widgets/desktop_error_view.dart';
import 'package:omninest/app/desktop/widgets/desktop_skeleton.dart';
import 'package:omninest/app/desktop/widgets/desktop_surfaces.dart';

import 'desktop_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('列表骨架的文本条是 66%×11 与 40%×9 的圆头条', (tester) async {
    await tester.pumpWidget(
      wrapDesktop(
        const Center(
          child: SizedBox(width: 600, child: DesktopSkeletonRows(count: 1)),
        ),
      ),
    );
    await tester.pump();

    final bars = find.byType(DesktopSkeletonBox);
    final sizes = [
      for (var i = 0; i < bars.evaluate().length; i++)
        tester.getSize(bars.at(i)),
    ];
    // 缩略 36 圆 + 11 高主条 + 9 高次条 + 64×12 尾部动作块。
    expect(sizes, contains(const Size(36, 36)));
    expect(sizes.any((size) => size.height == 11), isTrue);
    expect(sizes.any((size) => size.height == 9), isTrue);

    final main = sizes.firstWhere((size) => size.height == 11);
    final secondary = sizes.firstWhere((size) => size.height == 9);
    // 缩略 36 + 间距 14 + 尾部 16 + 动作块 64 = 130，余下 470 按比例分。
    expect(main.width, moreOrLessEquals(470 * 0.66, epsilon: 1));
    expect(secondary.width, moreOrLessEquals(470 * 0.40, epsilon: 1));
  });

  testWidgets('空态作为 status 主动播报', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      wrapDesktop(
        const Center(child: DesktopEmpty(message: 'Nothing here yet')),
      ),
    );
    await tester.pump();

    final data =
        tester.getSemantics(find.text('Nothing here yet')).getSemanticsData();
    expect(data.flagsCollection.isLiveRegion, isTrue);
    handle.dispose();
  });

  testWidgets('空态光晕章由图标与内边距撑出，不是写死直径', (tester) async {
    Future<Size> medallionOf(Widget empty) async {
      await tester.pumpWidget(wrapDesktop(Center(child: empty)));
      await tester.pump();
      final medallion =
          find
              .ancestor(
                of: find.byIcon(DesktopIcons.info),
                matching: find.byType(Container),
              )
              .first;
      return tester.getSize(medallion);
    }

    // 样例 `.empty .empty-ic{padding:16px}` + `<Icon size={24}>`，content-box。
    expect(
      await medallionOf(const DesktopEmpty(message: 'Empty')),
      const Size(56, 56),
    );
    // 样例 `.empty-sm .empty-ic{padding:11px}` + 18 图标。
    expect(
      await medallionOf(const DesktopEmpty(message: 'Empty', small: true)),
      const Size(40, 40),
    );
  });

  testWidgets('错误视图走桌面按钮，不再复用移动端的 FilledButton', (tester) async {
    var retried = 0;
    await tester.pumpWidget(
      wrapDesktop(
        DesktopErrorView(
          message: 'Something went wrong on this page.',
          onRetry: () => retried++,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Something went wrong on this page.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(retried, 1);
  });
}
