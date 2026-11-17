import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_page_view.dart';

/// 摘要：回归「模式切换回页模式后物理页滞留章首」的落位丢失。
///
/// 真实链路：ReaderPageView 挂载早于 PageNavigator 分页完成，
/// PageController(initialPage: 恢复目标) 因 item 数不足被钳制到 0；
/// 预热期页数经 pageCountNotifier 增长，恢复完成后 state.pageIndex 与
/// 挂载值相同，索引差异判定触发不了 _syncPageView，画面停在章首。
/// 修复 = 空闲期（无加载/边界/动画/拖拽）把物理页对齐到状态页，
/// 对齐回调产生的 onPageChanged 回声由恢复静默窗/闸门吞掉。
void main() {
  Future<_ReconcileHarnessState> pumpHarness(
    WidgetTester tester, {
    required ValueNotifier<int> pageCountNotifier,
    required int initialPageIndex,
    required int statePageCount,
    bool isPaginating = false,
  }) async {
    final harnessKey = GlobalKey<_ReconcileHarnessState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _ReconcileHarness(
            key: harnessKey,
            pageCountNotifier: pageCountNotifier,
            initialPageIndex: initialPageIndex,
            statePageCount: statePageCount,
            isPaginating: isPaginating,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return harnessKey.currentState!;
  }

  testWidgets('空闲期页数增长后物理页对齐到恢复目标', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final notifier = ValueNotifier<int>(0);
    addTearDown(notifier.dispose);
    final harness = await pumpHarness(
      tester,
      pageCountNotifier: notifier,
      initialPageIndex: 3,
      statePageCount: 0,
    );

    harness.gateActive = false;
    notifier.value = 5;
    await tester.pumpAndSettle();

    expect(harness.pageIndex, 3, reason: '对齐跳转后父级状态页应到达目标页');
    expect(harness.observedPages, [3]);
    expect(find.text('page-3'), findsOneWidget);
  });

  testWidgets('加载期不发生对齐跳转，加载结束后完成对齐', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final notifier = ValueNotifier<int>(0);
    addTearDown(notifier.dispose);
    final harness = await pumpHarness(
      tester,
      pageCountNotifier: notifier,
      initialPageIndex: 3,
      statePageCount: 0,
      isPaginating: true,
    );

    // 预热期页数增长发生在恢复定位期间，不得打断当前定位。
    notifier.value = 5;
    await tester.pumpAndSettle();
    harness.updateState(isPaginating: true, statePageCount: 5);
    await tester.pumpAndSettle();
    expect(harness.observedPages, isEmpty, reason: '加载期不得对齐跳转');

    // 恢复完成后闸门放行，重建（索引不变）触发对齐。
    harness.gateActive = false;
    harness.updateState(isPaginating: false, statePageCount: 5);
    await tester.pumpAndSettle();

    expect(harness.pageIndex, 3, reason: '闸门放行后的空闲期完成对齐');
    expect(harness.observedPages, [3]);
  });
}

class _ReconcileHarness extends StatefulWidget {
  const _ReconcileHarness({
    required this.pageCountNotifier,
    required this.initialPageIndex,
    required this.statePageCount,
    this.isPaginating = false,
    super.key,
  });

  final ValueNotifier<int> pageCountNotifier;
  final int initialPageIndex;
  final int statePageCount;
  final bool isPaginating;

  @override
  State<_ReconcileHarness> createState() => _ReconcileHarnessState();
}

class _ReconcileHarnessState extends State<_ReconcileHarness> {
  late int pageIndex = widget.initialPageIndex;
  late int statePageCount = widget.statePageCount;
  late bool isPaginating = widget.isPaginating;

  /// 复刻阅读器模式切换闸门：置 true 时 onPageChanged 回声被吞掉，
  /// 由测试用例在恢复放行节点显式关闭。
  bool gateActive = true;

  final List<int> observedPages = [];

  void updateState({required bool isPaginating, required int statePageCount}) {
    setState(() {
      this.isPaginating = isPaginating;
      this.statePageCount = statePageCount;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 刻意用 LayoutBuilder 包裹：复刻真实阅读页的 layout 回调路径。
    return LayoutBuilder(
      builder: (context, constraints) {
        return ReaderPageView(
          state: PagedState(
            chapterId: 'chapter-1',
            pageIndex: pageIndex,
            pageCount: statePageCount,
            hasMore: false,
            isPaginating: isPaginating,
          ),
          pageCountNotifier: widget.pageCountNotifier,
          pageBuilder: (index) => Text('page-$index'),
          callbacks: _ReconcileCallbacks(
            handlePageChanged: (index) {
              if (gateActive) {
                return;
              }
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

class _ReconcileCallbacks implements PageTurnCallbacks {
  _ReconcileCallbacks({required this.handlePageChanged});

  final void Function(int pageIndex) handlePageChanged;

  @override
  void onPageChanged(int pageIndex) => handlePageChanged(pageIndex);

  @override
  void onNextChapter() {}

  @override
  void onPreviousChapter() {}

  @override
  void onToggleControls() {}
}
