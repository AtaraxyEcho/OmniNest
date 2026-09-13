import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_page_view.dart';

/// 摘要：回归「LayoutBuilder 重建期间 setState」导致翻页点击失效与 build 崩溃。
///
/// 复刻真实调用链：命中热区 → PageView 翻页 → onPageChanged → 父级 setState
/// （父级处于 LayoutBuilder 之下）→ LayoutBuilder 重建 → didUpdateWidget 同步
/// jumpToPage → 再次 onPageChanged。修复前该链路会在 build 期间标记脏树，
/// 抛出 setState() called during build 并使后续翻页输入永久锁死。
void main() {
  testWidgets('LayoutBuilder 重建期间翻页不崩溃且点击右侧可持续翻页', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final harnessKey = GlobalKey<_PageTurnHarnessState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: _PageTurnHarness(key: harnessKey, pageCount: 8)),
      ),
    );
    expect(tester.takeException(), isNull);

    Future<void> tapNext() async {
      await tester.tapAt(const Offset(760, 300));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
    }

    await tapNext();
    expect(
      tester.takeException(),
      isNull,
      reason: '翻页不得在 build/layout 期间触发 setState',
    );
    expect(harnessKey.currentState!.pageIndex, 1);
    expect(harnessKey.currentState!.observedPages, [1]);

    // 输入锁必须释放：连续点击右侧应持续前进。
    await tapNext();
    await tapNext();
    expect(tester.takeException(), isNull);
    expect(harnessKey.currentState!.pageIndex, 3);
    expect(harnessKey.currentState!.observedPages, [1, 2, 3]);
  });

  testWidgets('外部翻页命令（底栏/快捷键）可持续翻页', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final harnessKey = GlobalKey<_PageTurnHarnessState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: _PageTurnHarness(key: harnessKey, pageCount: 8)),
      ),
    );

    Future<void> nextViaController() async {
      harnessKey.currentState!.controller.next();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
    }

    await nextViaController();
    await nextViaController();
    expect(tester.takeException(), isNull);
    expect(harnessKey.currentState!.pageIndex, 2);
    expect(harnessKey.currentState!.observedPages, [1, 2]);

    harnessKey.currentState!.controller.previous();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
    expect(harnessKey.currentState!.pageIndex, 1);
  });

  testWidgets('末页点击右侧切换到下一章而不锁死输入', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final harnessKey = GlobalKey<_PageTurnHarnessState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: _PageTurnHarness(key: harnessKey, pageCount: 1)),
      ),
    );

    await tester.tapAt(const Offset(760, 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
    expect(
      harnessKey.currentState!.nextChapterRequests,
      greaterThanOrEqualTo(1),
    );
    expect(harnessKey.currentState!.pageIndex, 0, reason: '换章请求不改变本页索引');
  });
}

class _PageTurnHarness extends StatefulWidget {
  const _PageTurnHarness({required this.pageCount, super.key});

  final int pageCount;

  @override
  State<_PageTurnHarness> createState() => _PageTurnHarnessState();
}

class _PageTurnHarnessState extends State<_PageTurnHarness> {
  final ReaderPageTurnController controller = ReaderPageTurnController();
  final List<int> observedPages = [];
  int pageIndex = 0;
  int nextChapterRequests = 0;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 刻意用 LayoutBuilder 包裹：复刻真实阅读页的 layout 回调路径。
    return LayoutBuilder(
      builder: (context, constraints) {
        return ReaderPageView(
          controller: controller,
          state: PagedState(
            chapterId: 'chapter-1',
            pageIndex: pageIndex,
            pageCount: widget.pageCount,
            hasMore: false,
            hasNextChapter: true,
          ),
          pageBuilder: (index) => Text('page-$index'),
          callbacks: _HarnessCallbacks(
            handlePageChanged: (index) {
              observedPages.add(index);
              setState(() => pageIndex = index);
            },
            handleNextChapter: () {
              nextChapterRequests++;
            },
          ),
          surfaceColor: Colors.white,
        );
      },
    );
  }
}

class _HarnessCallbacks implements PageTurnCallbacks {
  _HarnessCallbacks({
    required this.handlePageChanged,
    required this.handleNextChapter,
  });

  final void Function(int) handlePageChanged;
  final VoidCallback handleNextChapter;

  @override
  void onPageChanged(int pageIndex) => handlePageChanged(pageIndex);

  @override
  void onNextChapter() => handleNextChapter();

  @override
  void onPreviousChapter() {}

  @override
  void onToggleControls() {}
}
