import 'package:flutter/material.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_reading_runtime.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_layout_snapshot.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_runtime_diagnostics.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_viewport_snapshot.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_window_builder.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_continuous_scroll_controller.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_scroll_geometry_snapshot.dart';

/// B4 §48 WindowBuilder 单测：指纹纯计算、指纹门控、手势挂起、
/// 滑窗/前缀补偿分轨与 Live 几何装载。

ContinuousChapterEntry _chapter({required String id, double height = 2000}) {
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

class _FakeWindowDelegate implements ReaderWindowBuildDelegate {
  _FakeWindowDelegate(this.controller);

  final ReaderContinuousScrollController controller;
  String anchor = 'c0';
  double lastCumulativeHeight = 2000;
  List<String> windowChapterIds = const ['c0', 'c1', 'c2', 'c3'];
  int rebuildCount = 0;
  int ensureLayoutCount = 0;
  int slideCompensations = 0;
  int prefixCompensations = 0;
  int geometrySnapshots = 0;

  @override
  bool get isPageMode => false;

  @override
  bool get hasBuildData => true;

  @override
  String get anchorChapterId => anchor;

  @override
  List<String> get chapterIds => windowChapterIds;

  @override
  List<String> neighborIdsOf(String anchorChapterId) => const ['c1'];

  @override
  int? charCountOf(String chapterId) => 3200;

  @override
  ReaderWindowChapterSample? sampleChapter(String chapterId) =>
      ReaderWindowChapterSample(
        chapterId: chapterId,
        blockCount: 1,
        totalChars: 3200,
        hasPreciseHeights: true,
        lastCumulativeHeight: lastCumulativeHeight,
      );

  @override
  double get pageWidth => 400;

  @override
  double get textScale => 1.0;

  @override
  double get fontSize => 14;

  @override
  double get lineHeight => 1.5;

  @override
  String get fontFamily => 'test';

  @override
  bool get immersiveMode => false;

  @override
  bool get scrollAttached => false;

  @override
  double get currentScrollOffset => 0;

  @override
  double get viewportAnchorY => 0;

  @override
  bool get windowEmpty => controller.isEmpty;

  @override
  List<ContinuousChapterEntry> get entries => controller.entries;

  @override
  double prefixHeightOf(String chapterId) =>
      controller.prefixHeightOf(chapterId);

  @override
  VisualAnchor? visualAnchorAt(double windowContentY) => null;

  @override
  ReaderGeometrySnapshot buildGeometrySnapshot() {
    geometrySnapshots++;
    return controller.buildGeometrySnapshot();
  }

  @override
  void rebuildWindow({
    required String anchorChapterId,
    required List<String> chapterIds,
    required double pageWidth,
  }) {
    rebuildCount++;
    controller.rebuild(
      anchorChapterId: anchorChapterId,
      allChapterIds: chapterIds,
      // 章体高度跟随采样高度：终端装载的 Live 几何可直接断言
      // 「取最新 Candidate」语义。
      resolve: (id) => _chapter(id: id, height: lastCumulativeHeight),
    );
  }

  @override
  void ensureScrollLayoutForNeighbors(
    String anchorChapterId, {
    required double pageWidth,
    required double textScale,
  }) {
    ensureLayoutCount++;
  }

  @override
  void compensateWindowSlide({
    required List<ContinuousChapterEntry> prevEntries,
    required String? prevFirstId,
    required String? prevLastId,
    required double prevFirstHeight,
    required double prevLastHeight,
    required VisualAnchor? anchorBefore,
    required ReaderGeometrySnapshot geometryBefore,
    required double anchorContentY,
  }) {
    slideCompensations++;
  }

  @override
  void compensatePrefixDelta({
    required double? previousPrefix,
    required VisualAnchor? anchorBefore,
    required ReaderGeometrySnapshot geometryBefore,
    required double anchorContentY,
  }) {
    prefixCompensations++;
  }
}

ReaderWindowFingerprintInput _fingerprintInput({
  double lastHeight = 2000,
  bool hasPreciseHeights = true,
  int totalChars = 3200,
}) {
  return ReaderWindowFingerprintInput(
    anchorChapterId: 'c0',
    fontSize: 14,
    lineHeight: 1.5,
    fontFamily: 'test',
    immersiveMode: false,
    pageWidth: 400,
    textScale: 1.0,
    chapters: [
      ReaderWindowChapterSample(
        chapterId: 'c0',
        blockCount: 1,
        totalChars: totalChars,
        hasPreciseHeights: hasPreciseHeights,
        lastCumulativeHeight: lastHeight,
      ),
      const ReaderWindowChapterSample(chapterId: 'c1'),
    ],
  );
}

void main() {
  test('B4-指纹 纯计算：同输入同指纹；64px 桶内高度不换指纹，跨桶/精测态/字数换指纹', () {
    final base = ReaderWindowFingerprintCalculator.compute(_fingerprintInput());
    expect(
      ReaderWindowFingerprintCalculator.compute(_fingerprintInput()),
      base,
    );
    // 2010 与 2000 同属 64px 桶（31）：指纹不变。
    expect(
      ReaderWindowFingerprintCalculator.compute(
        _fingerprintInput(lastHeight: 2010),
      ),
      base,
    );
    // 2030 跨入桶 32：指纹变化。
    expect(
      ReaderWindowFingerprintCalculator.compute(
        _fingerprintInput(lastHeight: 2030),
      ),
      isNot(base),
    );
    expect(
      ReaderWindowFingerprintCalculator.compute(
        _fingerprintInput(hasPreciseHeights: false),
      ),
      isNot(base),
    );
    expect(
      ReaderWindowFingerprintCalculator.compute(
        _fingerprintInput(totalChars: 3201),
      ),
      isNot(base),
    );
  });

  test('B4-构建 首建装载 Live；指纹未变跳过；force 强制重建', () {
    final runtime = ReaderReadingRuntime();
    final controller = ReaderContinuousScrollController();
    final delegate = _FakeWindowDelegate(controller);
    runtime.windowBuilder.delegate = delegate;
    addTearDown(() {
      runtime.publisher.notifier.dispose();
      controller.dispose();
    });

    expect(runtime.windowBuilder.build(), isTrue);
    expect(delegate.rebuildCount, 1);
    expect(delegate.ensureLayoutCount, 1);
    expect(delegate.prefixCompensations, 1);
    expect(delegate.slideCompensations, 0);
    expect(runtime.geometry.live, isNotNull);

    // 指纹未变化：整段跳过，不触发 rebuild/几何采样（§61 图片不被扰动）。
    final snapshotsBefore = delegate.geometrySnapshots;
    expect(runtime.windowBuilder.build(), isFalse);
    expect(delegate.rebuildCount, 1);
    expect(delegate.geometrySnapshots, snapshotsBefore);

    // force：跳过指纹短路，真实重建。
    runtime.requestWindowCommit(force: true);
    expect(delegate.rebuildCount, 2);
  });

  test('B4-构建 手势活跃期构建挂起，终端旁路', () {
    final runtime = ReaderReadingRuntime();
    final controller = ReaderContinuousScrollController();
    final delegate = _FakeWindowDelegate(controller);
    runtime.windowBuilder.delegate = delegate;
    runtime.layoutProvider =
        () => ReaderLayoutSnapshot(
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
    addTearDown(() {
      runtime.dispose();
      runtime.publisher.notifier.dispose();
      controller.dispose();
    });

    runtime.onPointerDragStarted();
    expect(runtime.isInActiveGesture, isTrue);
    expect(runtime.windowBuilder.build(), isFalse);
    expect(delegate.rebuildCount, 0);

    // 终端构建（settle 路径）旁路手势守卫。
    expect(runtime.windowBuilder.build(deferIfGestureActive: false), isTrue);
    expect(delegate.rebuildCount, 1);
  });

  test('B4-构建 锚点章变化触发滑窗补偿分轨', () {
    final runtime = ReaderReadingRuntime();
    final controller = ReaderContinuousScrollController();
    final delegate = _FakeWindowDelegate(controller);
    runtime.windowBuilder.delegate = delegate;
    addTearDown(() {
      runtime.publisher.notifier.dispose();
      controller.dispose();
    });

    runtime.windowBuilder.build();
    expect(delegate.slideCompensations, 0);

    // 控制器窗口按 allChapterIds ±sideChapterCount 原序切片：锚点移至 c3
    // 后首章由 c0 变为 c2，构成真实滑窗（首章变化 → 滑窗补偿，
    // 前缀补偿分轨跳过）。
    delegate.anchor = 'c3';
    final prefixBefore = delegate.prefixCompensations;
    runtime.windowBuilder.build();
    expect(delegate.rebuildCount, 2);
    expect(delegate.entries.first.chapterId, 'c2');
    expect(delegate.slideCompensations, 1);
    expect(delegate.prefixCompensations, prefixBefore);
  });

  test('B5-场景D：滚动中多 Candidate 挂起，终端提交取最新状态装载', () {
    final runtime = ReaderReadingRuntime();
    final controller = ReaderContinuousScrollController();
    final delegate = _FakeWindowDelegate(controller);
    runtime.windowBuilder.delegate = delegate;
    runtime.layoutProvider =
        () => ReaderLayoutSnapshot(
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
    addTearDown(() {
      runtime.dispose();
      runtime.publisher.notifier.dispose();
      controller.dispose();
    });

    runtime.onPointerDragStarted();

    // Candidate A：测高收敛中间态 → 手势期间只登记挂起，不装载。
    delegate.lastCumulativeHeight = 2100;
    expect(runtime.windowBuilder.build(), isFalse);
    expect(runtime.geometry.live, isNull);
    expect(runtime.geometryScheduler.hasPendingCommit, isTrue);

    // Candidate B：收敛继续推进（滚动中的最新状态）。
    delegate.lastCumulativeHeight = 2600;
    expect(runtime.windowBuilder.build(), isFalse);
    expect(runtime.geometry.live, isNull);

    // 终端提交（settle 旁路）：取最新状态一次装载（§49）。
    expect(runtime.windowBuilder.build(deferIfGestureActive: false), isTrue);
    expect(runtime.geometry.live, isNotNull);
    expect(runtime.geometry.live!.chapterOf('c0')!.toEntry().totalHeight, 2600);
    expect(
      runtime.eventLog.events.any(
        (e) => e.type == ReaderRuntimeEventType.geometryCommitted,
      ),
      isTrue,
    );
    // 挂起随终端消费清零（_settle 路径）。
    expect(runtime.geometryScheduler.consumePendingCommit(), isTrue);
    expect(runtime.geometryScheduler.hasPendingCommit, isFalse);
  });
}
