import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/desktop/pages/desktop_reader_page.dart';

import 'desktop_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpReader(WidgetTester tester) async {
    tester.view.physicalSize = kDesktopViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: desktopSeedOverrides(),
        child: wrapDesktop(const DesktopReaderPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pump(const Duration(milliseconds: 320));
  }

  testWidgets('总览显示继续阅读卡与洞察计数', (tester) async {
    await pumpReader(tester);

    expect(find.textContaining('42 TITLES'), findsOneWidget);
    expect(find.text('The Quiet Arrival'), findsWidgets);
    expect(find.text('Ines Aoki'), findsWidgets);
    expect(find.textContaining('Kyoto'), findsWidgets);
    expect(find.text('64%'), findsOneWidget);
    // 洞察四卡：藏书 / 在读 / 已读完 / 未读。
    expect(find.text('Books'), findsWidgets);
    expect(find.text('1'), findsWidgets);
  });

  testWidgets('书库视图按书名搜索并可切列表', (tester) async {
    await pumpReader(tester);

    await tester.tap(find.text('Library'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(
      find.byKey(const ValueKey<String>('desktop-reader-search')),
      findsOneWidget,
    );
    expect(find.text('The Quiet Arrival'), findsWidgets);

    await tester.enterText(
      find.byKey(const ValueKey<String>('desktop-reader-search')),
      'quiet',
    );
    await tester.pump();
    expect(find.text('The Quiet Arrival'), findsWidgets);

    await tester.enterText(
      find.byKey(const ValueKey<String>('desktop-reader-search')),
      'zzz',
    );
    await tester.pump();
    expect(find.text('Nothing on the shelf yet.'), findsOneWidget);
  });

  testWidgets('筛到已读完时落到空态', (tester) async {
    await pumpReader(tester);
    // 洞察卡里也有 Finished 字样；分段控件在它下面，取最后一个。
    await tester.tap(find.text('Finished').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text('Nothing on the shelf yet.'), findsOneWidget);
  });

  testWidgets('在读筛选保留当前书', (tester) async {
    await pumpReader(tester);
    await tester.tap(find.text('In progress').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text('The Quiet Arrival'), findsWidgets);
  });
}
