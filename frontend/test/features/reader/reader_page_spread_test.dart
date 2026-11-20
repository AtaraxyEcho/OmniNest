import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_page_view.dart';

/// 摘要：样例 `.bookview .spread` 的跨页呈现。
///
/// 跨页只改呈现与步进：左页 `index`、右页 `index + 1`，一次翻两张；
/// 页码、页数与进度口径都不变，所以父级 progress 不需要知道跨页存在。
class _StubCallbacks implements PageTurnCallbacks {
  int? changed;
  bool prevChapter = false;
  bool nextChapter = false;

  @override
  void onPageChanged(int pageIndex) => changed = pageIndex;

  @override
  void onPreviousChapter() => prevChapter = true;

  @override
  void onNextChapter() => nextChapter = true;

  @override
  void onToggleControls() {}
}

void main() {
  Future<_StubCallbacks> pumpSpread(
    WidgetTester tester, {
    required bool spread,
    int pageIndex = 0,
    int pageCount = 4,
    PageTurnMode mode = PageTurnMode.cover,
  }) async {
    final callbacks = _StubCallbacks();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderPageView(
            state: PagedState(
              chapterId: 'c-1',
              pageIndex: pageIndex,
              pageCount: pageCount,
              hasMore: false,
              hasPreviousChapter: false,
              hasNextChapter: true,
            ),
            spread: spread,
            turnMode: mode,
            surfaceColor: Colors.white,
            callbacks: callbacks,
            pageBuilder:
                (index) =>
                    index < pageCount
                        ? Center(child: Text('page-$index'))
                        : null,
          ),
        ),
      ),
    );
    await tester.pump();
    return callbacks;
  }

  testWidgets('跨页模式并排渲染左右两页', (tester) async {
    await pumpSpread(tester, spread: true);

    expect(tester.takeException(), isNull);
    expect(find.text('page-0'), findsOneWidget);
    expect(find.text('page-1'), findsOneWidget);
    expect(find.byType(ReaderPageSpread), findsOneWidget);
  });

  testWidgets('单页模式只渲染当前页', (tester) async {
    await pumpSpread(tester, spread: false);

    expect(find.text('page-0'), findsOneWidget);
    expect(find.text('page-1'), findsNothing);
    expect(find.byType(ReaderPageSpread), findsNothing);
  });

  testWidgets('跨页模式下前进一步跳过两张', (tester) async {
    final controller = ReaderPageTurnController();
    addTearDown(controller.dispose);
    final callbacks = _StubCallbacks();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderPageView(
            state: PagedState(
              chapterId: 'c-1',
              pageIndex: 0,
              pageCount: 4,
              hasMore: false,
              hasPreviousChapter: false,
              hasNextChapter: true,
            ),
            spread: true,
            turnMode: PageTurnMode.cover,
            controller: controller,
            surfaceColor: Colors.white,
            callbacks: callbacks,
            pageBuilder:
                (index) =>
                    index < 4 ? Center(child: Text('page-$index')) : null,
          ),
        ),
      ),
    );
    await tester.pump();

    controller.next();
    await tester.pump();
    // 翻页动画按样例 `leaf 820ms`，等它跑完再断言。
    await tester.pump(const Duration(milliseconds: 900));

    expect(callbacks.changed, 2);
  });

  testWidgets('右页越界时留白，不借用越界内容', (tester) async {
    await pumpSpread(tester, spread: true, pageIndex: 3, pageCount: 4);

    // 页数 4 的最后一页是奇数页：右页空白，只有左侧一张。
    expect(find.text('page-3'), findsOneWidget);
    expect(find.text('page-4'), findsNothing);
  });

  testWidgets('ReaderPageSpread 支持整幅 curlOverlay 叠加渲染', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: ReaderPageSpread(
              left: Center(child: Text('L')),
              right: Center(child: Text('R')),
              surfaceColor: Color(0xFFF6F1E4),
              curlOverlay: SizedBox.expand(
                key: ValueKey('spread-curl-overlay'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('spread-curl-overlay')), findsOneWidget);
  });
}
