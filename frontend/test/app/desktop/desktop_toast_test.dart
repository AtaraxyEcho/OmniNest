import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_toast.dart';

import 'desktop_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> pumpToasts(WidgetTester tester) async {
    tester.view.physicalSize = kDesktopViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: wrapDesktop(const Stack(children: [DesktopToasts()])),
      ),
    );
    await tester.pump();
    return ProviderScope.containerOf(
      tester.element(find.byType(DesktopToasts)),
    );
  }

  testWidgets('提示入栈后可见，到期自行退场', (tester) async {
    final container = await pumpToasts(tester);
    container
        .read(desktopToastProvider.notifier)
        .show('Queue cleared', icon: DesktopIcons.check);

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Queue cleared'), findsOneWidget);

    // 4.2s 生命 + 300ms 退场，之后从栈里移除。
    await tester.pump(const Duration(milliseconds: 4300));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Queue cleared'), findsNothing);
    expect(container.read(desktopToastProvider), isEmpty);
  });

  testWidgets('带动作的提示点动作后执行回调并立刻收起', (tester) async {
    final container = await pumpToasts(tester);
    var acted = false;
    container
        .read(desktopToastProvider.notifier)
        .show(
          'Watch history cleared',
          actionLabel: 'Undo',
          onAction: () => acted = true,
        );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Watch history cleared'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(acted, isTrue);
    expect(find.text('Watch history cleared'), findsNothing);
  });

  testWidgets('多条提示纵向堆叠，互不覆盖', (tester) async {
    final container = await pumpToasts(tester);
    container.read(desktopToastProvider.notifier)
      ..show('First')
      ..show('Second');

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final first = tester.getRect(find.text('First'));
    final second = tester.getRect(find.text('Second'));
    expect(first.bottom, lessThan(second.top));
  });

  testWidgets('提示最多保留 4 条，删除类图标推断为错误语义', (tester) async {
    final container = await pumpToasts(tester);
    container.read(desktopToastProvider.notifier)
      ..show('One')
      ..show('Two')
      ..show('Three')
      ..show('Four')
      ..show('Five', icon: DesktopIcons.trash);

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final state = container.read(desktopToastProvider);
    expect(state, hasLength(4));
    expect(state.first.message, 'Two');
    expect(state.last.kind, DesktopToastKind.error);
    expect(find.text('One'), findsNothing);
  });

  testWidgets('关闭钮有可访问名称，读屏能播报提示', (tester) async {
    final handle = tester.ensureSemantics();
    final container = await pumpToasts(tester);
    container.read(desktopToastProvider.notifier).show('Metadata saved');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 只有图标的关闭钮必须带 Close 的提示，否则读屏念不出来。
    expect(find.byTooltip('Close'), findsOneWidget);
    final region = tester.getSemantics(find.text('Metadata saved'));
    expect(region.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
    handle.dispose();
  });
}
