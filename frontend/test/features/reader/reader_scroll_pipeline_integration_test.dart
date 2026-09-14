import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_layout_snapshot.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_position_snapshot.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_reading_runtime.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_runtime_diagnostics.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_viewport_snapshot.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_continuous_scroll_controller.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_continuous_scroll_view.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// §114/§118/§122/§35/§117 滚动管线集成测试（新方案 §5/§7 信号契约）：
/// 真实 ReaderContinuousScrollView + 真实控制器 + 真实 Runtime 编排器。
/// 指针/ScrollEnd 信号直达 Runtime，事务决策全部内化。

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

  int get startedCount =>
      runtime.eventLog.events
          .where((e) => e.type == ReaderRuntimeEventType.transactionStarted)
          .length;

  int? get startedTxId =>
      runtime.eventLog.events
          .where((e) => e.type == ReaderRuntimeEventType.transactionStarted)
          .firstOrNull
          ?.transactionId;

  bool get hasCompletedEvent => runtime.eventLog.events.any(
    (e) => e.type == ReaderRuntimeEventType.transactionCompleted,
  );

  @override
  void initState() {
    super.initState();
    controller = ReaderContinuousScrollController();
    controller.rebuild(
      anchorChapterId: 'c0',
      allChapterIds: const ['c0', 'c1'],
      resolve: (id) => _chapter(id: id),
    );
    runtime.layoutProvider = _buildLiveLayout;
    runtime.onMetricsCommitRequested = () {};
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
    final layout = tx?.layout ?? _buildLiveLayout();
    final snapshot = runtime.position.resolve(
      scrollOffset: offset,
      layout: layout,
      transactionId: tx?.id ?? 0,
    );
    if (snapshot != null) {
      snapshots.add(snapshot);
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
        onPointerDragStarted: runtime.onPointerDragStarted,
        onPointerReleased: runtime.onPointerReleased,
        onPhysicalScrollEnd: runtime.onPhysicalScrollEnd,
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
  testWidgets('§114 拖动全程一个事务：信号进 Runtime，提交后结束', (tester) async {
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
    await tester.pump(const Duration(milliseconds: 200));

    // 新方案 §5/§7：一次手势恰一个事务，settling 后提交结束。
    expect(harness.startedCount, 1);
    expect(harness.snapshots, isNotEmpty);
    for (final snapshot in harness.snapshots) {
      expect(snapshot.transactionId, harness.startedTxId);
    }
    expect(harness.hasCompletedEvent, isTrue);
    expect(harness.runtime.transactions.current, isNull);
  });

  testWidgets('§118 拖动中后台测高替换 Live 几何，事务内快照仍用冻结布局', (tester) async {
    final harness = await _pumpHarness(tester);

    final origin = tester.getCenter(find.byType(ReaderContinuousScrollView));
    final gesture = await tester.startGesture(origin);
    // 首个增量被手势竞技场消耗（只触发拖动信号），先小步后正式滚动。
    await gesture.moveBy(const Offset(0, -30));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -100));
    await tester.pump();
    expect(harness.snapshots, isNotEmpty);
    final frozenRevision =
        harness.snapshots.last.layoutRevision.geometryRevision;

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
    await tester.pump(const Duration(milliseconds: 200));

    expect(harness.snapshots, isNotEmpty);
    for (final snapshot in harness.snapshots) {
      expect(snapshot.layoutRevision.geometryRevision, frozenRevision);
    }
  });

  testWidgets('§35/§117 程序化 jumpTo 不产生用户拖动事务', (tester) async {
    final harness = await _pumpHarness(tester);

    harness.scrollController.jumpTo(200);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 200));

    // ScrollEnd 只是信号：无指针手势则无事务创建。
    expect(harness.startedCount, 0);
    expect(harness.runtime.transactions.current, isNull);
    expect(harness.snapshots, isNotEmpty);
    for (final snapshot in harness.snapshots) {
      expect(snapshot.transactionId, 0);
    }
  });
}
