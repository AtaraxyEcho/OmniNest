import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_page_view.dart';

/// 摘要：PageTurn 专项回归（方案 §36-42）——图片页右侧点击必须与文本页
/// 同规则翻页。图片组件内部的预览/重试 GestureDetector 不得吞掉顶层
/// 翻页热区；闸门临时阻塞后必须恢复，不得永久死锁。
void main() {
  Future<void> pumpHarness(
    WidgetTester tester,
    GlobalKey<_ImagePageHarnessState> harnessKey, {
    required bool imagePage,
    int pageCount = 8,
    int contentPages = 8,
    bool hasMore = false,
    bool hasNextChapter = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _ImagePageHarness(
            key: harnessKey,
            imagePage: imagePage,
            pageCount: pageCount,
            contentPages: contentPages,
            hasMore: hasMore,
            hasNextChapter: hasNextChapter,
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  }

  testWidgets('图片独占页右侧点击翻下一页（预览手势不吞翻页事件）', (tester) async {
    final harnessKey = GlobalKey<_ImagePageHarnessState>();
    await pumpHarness(tester, harnessKey, imagePage: true);

    await tester.tapAt(const Offset(760, 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
    expect(harnessKey.currentState!.pageIndex, 1);
  });

  testWidgets('图片页连续右侧点击持续翻页，无 3→3 停滞', (tester) async {
    final harnessKey = GlobalKey<_ImagePageHarnessState>();
    await pumpHarness(tester, harnessKey, imagePage: true);

    Future<void> tapNext() async {
      await tester.tapAt(const Offset(760, 300));
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump(const Duration(milliseconds: 120));
    }

    await tapNext();
    await tapNext();
    await tapNext();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(harnessKey.currentState!.pageIndex, 3);
    expect(harnessKey.currentState!.observedPages, [1, 2, 3]);
  });

  testWidgets('闸门临时阻塞后恢复：isPaginating 期间不翻页，解除后立即生效', (tester) async {
    final harnessKey = GlobalKey<_ImagePageHarnessState>();
    await pumpHarness(tester, harnessKey, imagePage: false);

    harnessKey.currentState!.setPaginating(true);
    await tester.pump();

    await tester.tapAt(const Offset(760, 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(harnessKey.currentState!.pageIndex, 0, reason: '分页中点击不得翻页');

    harnessKey.currentState!.setPaginating(false);
    await tester.pump();

    await tester.tapAt(const Offset(760, 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
    expect(harnessKey.currentState!.pageIndex, 1, reason: '闸门必须最终释放');
  });

  testWidgets('图片加载失败占位页（重试手势）右侧点击仍可翻页', (tester) async {
    final harnessKey = GlobalKey<_ImagePageHarnessState>();
    await pumpHarness(tester, harnessKey, imagePage: false);

    // 首页用失败占位渲染：重试 GestureDetector 同样不得吞翻页事件。
    harnessKey.currentState!.setFailedPlaceholder(true);
    await tester.pump();

    await tester.tapAt(const Offset(760, 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
    expect(harnessKey.currentState!.pageIndex, 1);
  });

  testWidgets('边界请求超时后闸门释放，可再次请求（PT-2/PT-5）', (tester) async {
    final harnessKey = GlobalKey<_ImagePageHarnessState>();
    await pumpHarness(
      tester,
      harnessKey,
      imagePage: false,
      pageCount: 1,
      hasNextChapter: true,
    );

    // 末页右击 → 边界请求；闸门临时阻塞期内重复点击被吞。
    await tester.tapAt(const Offset(760, 300));
    await tester.pump();
    expect(harnessKey.currentState!.nextChapterRequests, 1);

    await tester.tapAt(const Offset(760, 300));
    await tester.pump();
    expect(
      harnessKey.currentState!.nextChapterRequests,
      1,
      reason: '边界请求进行中不得重复派发',
    );

    // 超时复位（1200ms）后闸门必须释放，再次点击重新有效。
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.tapAt(const Offset(760, 300));
    await tester.pump();
    expect(harnessKey.currentState!.nextChapterRequests, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('探测页无内容时转边界请求，闸门释放后扩窗可续读（PT-3）', (tester) async {
    final harnessKey = GlobalKey<_ImagePageHarnessState>();
    await pumpHarness(
      tester,
      harnessKey,
      imagePage: false,
      pageCount: 2,
      hasMore: true,
      contentPages: 2,
      hasNextChapter: true,
    );

    // 翻到第 1 页。
    await tester.tapAt(const Offset(760, 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(harnessKey.currentState!.pageIndex, 1);

    // 再右击进入探测页（pageBuilder 返回 null）→ 转边界请求。
    await tester.tapAt(const Offset(760, 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      harnessKey.currentState!.nextChapterRequests,
      1,
      reason: '探测失败必须转边界请求而不是卡死',
    );

    // 超时复位后模拟下一章就绪（真实流程中边界请求触发扩窗预热），
    // 再次右击必须正常翻页：闸门不得残留阻塞。
    await tester.pump(const Duration(milliseconds: 1300));
    harnessKey.currentState!.expandNextChapter();
    await tester.pump();
    await tester.tapAt(const Offset(760, 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
    expect(harnessKey.currentState!.pageIndex, 2, reason: '闸门必须最终释放');
  });
}

class _ImagePageHarness extends StatefulWidget {
  const _ImagePageHarness({
    required this.imagePage,
    this.pageCount = 8,
    this.contentPages = 8,
    this.hasMore = false,
    this.hasNextChapter = false,
    super.key,
  });

  /// true：当前页渲染图片独占页（含预览 GestureDetector）。
  final bool imagePage;

  /// 状态里的总页数（PagedState.pageCount）。
  final int pageCount;

  /// 实际有内容的页数；index >= contentPages 时 pageBuilder 返回 null。
  final int contentPages;

  final bool hasMore;
  final bool hasNextChapter;

  @override
  State<_ImagePageHarness> createState() => _ImagePageHarnessState();
}

class _ImagePageHarnessState extends State<_ImagePageHarness> {
  final ReaderPageTurnController controller = ReaderPageTurnController();
  final List<int> observedPages = [];
  int pageIndex = 0;
  int nextChapterRequests = 0;
  late int pageCount = widget.pageCount;
  late int contentPages = widget.contentPages;
  bool paginating = false;
  bool failedPlaceholder = false;

  void setPaginating(bool value) {
    setState(() => paginating = value);
  }

  void setFailedPlaceholder(bool value) {
    setState(() => failedPlaceholder = value);
  }

  /// 模拟边界请求后的扩窗：下一章就绪，探测页变为真实页。
  void expandNextChapter() {
    setState(() {
      contentPages++;
      pageCount++;
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return ReaderPageView(
          controller: controller,
          state: PagedState(
            chapterId: 'chapter-1',
            pageIndex: pageIndex,
            pageCount: pageCount,
            hasMore: widget.hasMore,
            hasNextChapter: widget.hasNextChapter,
            isPaginating: paginating,
          ),
          pageBuilder: (index) {
            if (index >= contentPages) {
              return null;
            }
            if (failedPlaceholder && index == pageIndex) {
              // 模拟图片加载失败占位：内嵌重试 GestureDetector。
              return GestureDetector(
                onTap: () {},
                child: const SizedBox.expand(
                  child: ColoredBox(color: Colors.grey),
                ),
              );
            }
            if (widget.imagePage || index == 1) {
              // 模拟图片独占页：铺满整页的预览 GestureDetector。
              return GestureDetector(
                onTap: () {},
                child: const SizedBox.expand(
                  child: ColoredBox(color: Colors.blue),
                ),
              );
            }
            return Text('page-$index');
          },
          callbacks: _ImageHarnessCallbacks(
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

class _ImageHarnessCallbacks implements PageTurnCallbacks {
  _ImageHarnessCallbacks({
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
