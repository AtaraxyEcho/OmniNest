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
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _ImagePageHarness(key: harnessKey, imagePage: imagePage),
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
}

class _ImagePageHarness extends StatefulWidget {
  const _ImagePageHarness({
    required this.imagePage,
    super.key,
  });

  /// true：当前页渲染图片独占页（含预览 GestureDetector）。
  final bool imagePage;

  @override
  State<_ImagePageHarness> createState() => _ImagePageHarnessState();
}

class _ImagePageHarnessState extends State<_ImagePageHarness> {
  final ReaderPageTurnController controller = ReaderPageTurnController();
  final List<int> observedPages = [];
  int pageIndex = 0;
  bool paginating = false;
  bool failedPlaceholder = false;

  void setPaginating(bool value) {
    setState(() => paginating = value);
  }

  void setFailedPlaceholder(bool value) {
    setState(() => failedPlaceholder = value);
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
            pageCount: 8,
            hasMore: false,
            isPaginating: paginating,
          ),
          pageBuilder: (index) {
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
          ),
          surfaceColor: Colors.white,
        );
      },
    );
  }
}

class _ImageHarnessCallbacks implements PageTurnCallbacks {
  _ImageHarnessCallbacks({required this.handlePageChanged});

  final void Function(int) handlePageChanged;

  @override
  void onPageChanged(int pageIndex) => handlePageChanged(pageIndex);

  @override
  void onNextChapter() {}

  @override
  void onPreviousChapter() {}

  @override
  void onToggleControls() {}
}
