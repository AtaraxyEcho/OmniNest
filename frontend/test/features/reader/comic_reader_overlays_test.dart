import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/reader/presentation/widgets/comic_reader_overlays.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

void main() {
  Widget buildApp(Widget child) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Stack(children: [child])),
    );
  }

  testWidgets('漫画顶部栏转发返回与阅读模式切换操作', (tester) async {
    var backCount = 0;
    var switchCount = 0;
    var contentsCount = 0;

    await tester.pumpWidget(
      buildApp(
        ComicReaderTopBar(
          catalogTitle: '第一卷',
          isPageMode: true,
          settings: ReaderViewSettings(paletteId: 'dark'),
          onBack: () => backCount++,
          onShowContents: () => contentsCount++,
          onShowSettings: () {},
          onShowShortcuts: () {},
          onSwitchReadingMode: () => switchCount++,
        ),
      ),
    );

    expect(find.text('第一卷'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.tap(find.byIcon(Icons.swap_vert_rounded));
    await tester.tap(find.byIcon(Icons.toc_rounded));

    expect(backCount, 1);
    expect(switchCount, 1);
    expect(contentsCount, 1);
  });

  testWidgets('漫画页码指示器显示当前页与总页数', (tester) async {
    await tester.pumpWidget(
      buildApp(const ComicPageIndicator(currentPageIndex: 2, totalPages: 7)),
    );

    expect(find.text('3 / 7'), findsOneWidget);
  });

  testWidgets('漫画底栏在窄屏下收起次要操作且不溢出', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      buildApp(
        ComicReaderBottomBar(
          currentPageIndex: 2,
          totalPages: 12,
          isPageMode: true,
          settings: ReaderViewSettings(paletteId: 'dark'),
          onPrevious: () {},
          onNext: () {},
          onSeek: (_) {},
          onShowContents: () {},
          onSwitchReadingMode: () {},
        ),
      ),
    );

    expect(find.text('3 / 12'), findsOneWidget);
    // 模式切换钮在移动端恢复常驻（样例底栏），窄屏不溢出为准。
    expect(find.byIcon(Icons.swap_vert_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('漫画控制层在短横屏和放大字体下不溢出', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(640, 360);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(640, 360),
          textScaler: TextScaler.linear(1.5),
        ),
        child: buildApp(
          Stack(
            children: [
              ComicReaderTopBar(
                catalogTitle: '横屏下很长的漫画卷册标题用于验证布局',
                isPageMode: false,
                settings: ReaderViewSettings(paletteId: 'dark'),
                onBack: () {},
                onShowContents: () {},
                onShowSettings: () {},
                onShowShortcuts: () {},
                onSwitchReadingMode: () {},
              ),
              ComicReaderBottomBar(
                currentPageIndex: 98,
                totalPages: 240,
                isPageMode: false,
                settings: ReaderViewSettings(paletteId: 'dark'),
                onPrevious: () {},
                onNext: () {},
                onSeek: (_) {},
                onShowContents: () {},
                onSwitchReadingMode: () {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('99 / 240'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
