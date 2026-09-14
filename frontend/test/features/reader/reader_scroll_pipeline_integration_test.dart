import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_layout_snapshot.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_position_snapshot.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_reading_runtime.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_transaction.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_viewport_snapshot.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_continuous_scroll_controller.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_continuous_scroll_view.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// §114-§117/§122 滚动管线集成测试：真实 ReaderContinuousScrollView +
/// 真实控制器 + 真实 Runtime（事务/解析器/Publisher），消费侧复刻页面
/// 的 onActualScrollOffsetChanged / 相位转移语义（§84/§87）。

ContinuousChapterEntry _chapter({required String id, double height = 2000}) {
  // 长正文保证真实渲染高度超过视口，拖动可产生实际滚动位移。
  final body = List.filled(400, '段落文本内容示例').join();
  final block = ParagraphBlock(
    lines: [
      LineData(spans: [ReaderInlineSpan(text: body)]),
    ],
  );
  return ContinuousChapterEntry(
    chapterId: id,
    title: id,
    blockCount: 1,
    cumulativeHeights: [height],
    totalHeight: height,
    totalChars: body.length,
    isReady: true,
    blocks: [block],
    blockCharPrefixes: [0, body.length],
  );
}

class _Harness extends StatefulWidget {
  const _Harness({super.key});

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  final runtime = ReaderReadingRuntime();
  late final ReaderContinuousScrollController controller;
  final scrollController = ScrollController();
  final snapshots = <ReaderPositionSnapshot>[];
  final phases = <ReaderScrollPhase>[];
  int transactionsBegun = 0;
  int? txIdAtBegin;
  int? txIdAtSettling;
  int? geometryRevisionAtBegin;

  @override
  void initState() {
    super.initState();
    controller = ReaderContinuousScrollController();
    controller.rebuild(
      anchorChapterId: 'c0',
      allChapterIds: const ['c0', 'c1'],
      resolve: (id) => _chapter(id: id),
    );
  }

  @override
  void dispose() {
    scrollController.dispose();
    controller.dispose();
    runtime.publisher.notifier.dispose();
    super.dispose();
  }

  ReaderLayoutSnapshot _buildLiveLayout() {
    return ReaderLayoutSnapshot(
      geometry: controller.buildGeometrySnapshot(),
      viewport: const ReaderViewportSnapshot(
        viewportSize: Size(400, 800),
        anchorY: 0,
        contentWidth: 400,
        textScale: 1.0,
        safeAreaTop: 0,
        safeAreaBottom: 0,
      ),
      windowRevision: controller.windowRevision,
    );
  }

  void _onOffsetChanged(double offset) {
    final tx = runtime.transactions.current;
    if (tx != null && tx.phase == ReaderTransactionPhase.cancelled) {
      return;
    }
    final snapshot = runtime.position.resolve(
      scrollOffset: offset,
      layout: tx?.layout ?? _buildLiveLayout(),
      transactionId: tx?.id ?? 0,
    );
    if (snapshot != null) {
      snapshots.add(snapshot);
    }
  }

  void _onPhaseChanged(ReaderScrollPhase phase) {
    phases.add(phase);
    switch (phase) {
      case ReaderScrollPhase.userDragging:
        final tx = runtime.transactions.beginOrReplace(
          kind: ReaderTransactionKind.userDrag,
          layout: _buildLiveLayout(),
          initialOffset:
              scrollController.hasClients ? scrollController.offset : 0,
          initialVisualProgress: runtime.publisher.notifier.value,
        );
        transactionsBegun++;
        txIdAtBegin = tx.id;
        geometryRevisionAtBegin = tx.layout.geometry.revision;
      case ReaderScrollPhase.settling:
        final tx = runtime.transactions.current;
        txIdAtSettling = tx?.id;
        if (tx != null) {
          runtime.transactions.finish(tx.id);
        }
      case ReaderScrollPhase.ballistic:
      case ReaderScrollPhase.idle:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ReaderContinuousScrollView(
        controller: controller,
        settings: ReaderViewSettings(),
        scrollController: scrollController,
        itemId: 'book',
        annotationsByChapter: const {},
        onScrollOffsetChanged: _onOffsetChanged,
        onScrollPhaseChanged: _onPhaseChanged,
      ),
    );
  }
}

Future<_HarnessState> _pumpHarness(WidgetTester tester) async {
  final key = GlobalKey<_HarnessState>();
  await tester.pumpWidget(MaterialApp(home: _Harness(key: key)));
  await tester.pumpAndSettle();
  return key.currentState!;
}

void main() {
  testWidgets('§114 拖动全程一个事务：userDragging→ballistic→settling 后结束', (
    tester,
  ) async {
    final harness = await _pumpHarness(tester);

    final origin = tester.getCenter(find.byType(ReaderContinuousScrollView));
    final gesture = await tester.startGesture(origin);
    await gesture.moveBy(const Offset(0, -80));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -120));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -120));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    // 相位序列：阈值拖动 → 手指离开 → ScrollEnd。
    expect(harness.phases, [
      ReaderScrollPhase.userDragging,
      ReaderScrollPhase.ballistic,
      ReaderScrollPhase.settling,
    ]);
    // §23/§114：一次手势只开一个事务。
    expect(harness.transactionsBegun, 1);
    expect(harness.snapshots, isNotEmpty);
    // 事务内解析的快照全部同源（事务 id + 冻结几何版本）。
    for (final snapshot in harness.snapshots) {
      expect(snapshot.transactionId, harness.txIdAtBegin);
      expect(
        snapshot.layoutRevision.geometryRevision,
        harness.geometryRevisionAtBegin,
      );
    }
    // §122：settling 触发时事务仍在（提交完成后才结束）。
    expect(harness.txIdAtSettling, harness.txIdAtBegin);
    // 事务在提交后结束。
    expect(harness.runtime.transactions.current, isNull);
  });

  testWidgets('§118 拖动中后台测高替换 Live 几何，事务内快照仍用冻结布局', (tester) async {
    final harness = await _pumpHarness(tester);
    final frozenRevision = harness.geometryRevisionAtBegin;

    final origin = tester.getCenter(find.byType(ReaderContinuousScrollView));
    final gesture = await tester.startGesture(origin);
    await gesture.moveBy(const Offset(0, -100));
    await tester.pump();

    // 模拟后台测高完成并应用：Live 几何版本前进。
    harness.controller.rebuild(
      anchorChapterId: 'c0',
      allChapterIds: const ['c0', 'c1'],
      resolve: (id) => _chapter(id: id, height: 2600),
    );
    await tester.pump();
    expect(harness.controller.geometryRevision, isNot(frozenRevision));

    await gesture.moveBy(const Offset(0, -100));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(harness.snapshots, isNotEmpty);
    // 全部快照仍以事务冻结布局解析，Live 版本变化不穿透。
    for (final snapshot in harness.snapshots) {
      expect(
        snapshot.layoutRevision.geometryRevision,
        harness.geometryRevisionAtBegin,
      );
    }
  });

  testWidgets('§35/§117 程序化 jumpTo 不产生用户拖动事务', (tester) async {
    final harness = await _pumpHarness(tester);

    harness.scrollController.jumpTo(200);
    await tester.pumpAndSettle();

    // ScrollNotification 派发 settling，但没有任何指针手势 → 无事务创建。
    expect(harness.phases, [ReaderScrollPhase.settling]);
    expect(harness.transactionsBegun, 0);
    expect(harness.runtime.transactions.current, isNull);
    // 无事务期解析使用 Live 布局：transactionId == 0。
    expect(harness.snapshots, isNotEmpty);
    for (final snapshot in harness.snapshots) {
      expect(snapshot.transactionId, 0);
    }
  });
}
