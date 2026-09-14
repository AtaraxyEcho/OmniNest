import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_consume_delegate.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_layout_snapshot.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_position_snapshot.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_reading_runtime.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_runtime_diagnostics.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_scroll_effect.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_viewport_snapshot.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_continuous_scroll_controller.dart';

/// B3 §6.4 consume 管线 Runtime 直驱单测（§123/§124 纯 Dart，无 Widget 树）：
/// 手势挂起/终端提交、收敛抑制、去重持久化。
/// 章体 2000px / 3200 字符（'段落文本内容示例'×400），charOffset≈contentY×1.6。

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

class _FakeScrollEffect implements ReaderScrollEffect {
  double offsetValue = 0;

  @override
  bool get hasClients => true;

  @override
  double get offset => offsetValue;

  @override
  double get maxScrollExtent => 4000;

  @override
  Future<void> animateTo(
    double offset, {
    required Duration duration,
    required Curve curve,
  }) async {
    offsetValue = offset;
  }

  @override
  void jumpTo(double offset) {
    offsetValue = offset;
  }
}

class _FakeDelegate implements ReaderConsumeDelegate {
  final totalChars = <String, int>{'c0': 3200, 'c1': 3200};
  final converging = <String>{};
  double chapterProgress = 0;
  int trackerUpdates = 0;
  final persisted = <int>[];
  final adopted = <String>[];
  int expandForward = 0;
  int expandBackward = 0;
  int preloadTail = 0;
  int preloadThrottled = 0;

  @override
  int totalCharsOf(String chapterId) => totalChars[chapterId] ?? 0;

  @override
  bool isChapterHeightConverging(String chapterId) =>
      converging.contains(chapterId);

  @override
  void dismissReturnControl() {}

  @override
  void preloadAdjacentAtTail() => preloadTail++;

  @override
  void preloadAdjacentThrottled() => preloadThrottled++;

  @override
  void adoptChapter(String chapterId) => adopted.add(chapterId);

  @override
  void expandWindow({required bool forward}) =>
      forward ? expandForward++ : expandBackward++;

  @override
  void confirmAppliedPosition({
    required ReaderPositionSnapshot snapshot,
    required int totalChars,
  }) {
    trackerUpdates++;
  }

  @override
  void persistProgress({
    required String chapterId,
    required int charOffset,
    required double chapterProgress,
  }) {
    // 与真实页面一致：持久化即更新章内进度显示值（影响收敛抑制比较）。
    this.chapterProgress = chapterProgress;
    persisted.add(charOffset);
  }

  @override
  double visualProgressFallback(String chapterId, double chapterVisualCursor) =>
      0.5;

  @override
  double get currentChapterProgress => chapterProgress;
}

class _Pipeline {
  final runtime = ReaderReadingRuntime();
  final effect = _FakeScrollEffect();
  final delegate = _FakeDelegate();
  final controller = ReaderContinuousScrollController();
  final settleAdopted = <String>[];
  final settleExpands = <bool>[];

  late double _chapterHeight;

  _Pipeline({
    double chapterHeight = 2000,
    List<String> chapterIds = const ['c0', 'c1'],
  }) {
    _chapterHeight = chapterHeight;
    runtime.scrollEffect = effect;
    runtime.consumeDelegate = delegate;
    runtime.anchorChapterId = 'c0';
    runtime.layoutProvider = _buildLiveLayout;
    runtime.onAdoptChapterRequested = settleAdopted.add;
    runtime.onExpandWindowRequested =
        ({required bool forward}) => settleExpands.add(forward);
    controller.rebuild(
      anchorChapterId: chapterIds.first,
      allChapterIds: chapterIds,
      resolve: (id) => _chapter(id: id, height: _chapterHeight),
    );
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

  /// 以当前 effect offset 驱动一次消费管线。
  void feed() {
    runtime.onPhysicalOffsetChanged(effect.offsetValue);
  }

  void rebuildWithHeight(double height) {
    _chapterHeight = height;
    controller.rebuild(
      anchorChapterId: 'c0',
      allChapterIds: const ['c0', 'c1'],
      resolve: (id) => _chapter(id: id, height: height),
    );
  }

  void dispose() {
    runtime.dispose();
    controller.dispose();
    runtime.publisher.notifier.dispose();
  }
}

void main() {
  test('B3-1 手势挂起/终端提交：事务内收养与扩窗挂起，settle 一次提交', () {
    final pipeline = _Pipeline();
    addTearDown(pipeline.dispose);
    final runtime = pipeline.runtime;

    runtime.onPointerDragStarted();
    final tx = runtime.transactions.current!;

    pipeline.effect.offsetValue = 300;
    pipeline.feed();
    final firstCharOffset = runtime.positionState.transient!.charOffset;
    // 首帧应用：transient 已接受，committed 未固化，阈值直过。
    expect(runtime.positionState.transient, isNotNull);
    expect(runtime.positionState.transient!.transactionId, tx.id);
    expect(runtime.positionState.committed, isNull);
    expect(pipeline.delegate.persisted, [firstCharOffset]);
    expect(pipeline.delegate.trackerUpdates, 1);

    // 尾部帧：事务期间收养/扩窗只挂起，不直接执行。
    pipeline.effect.offsetValue = 3900;
    pipeline.feed();
    expect(tx.pendingChapterId, 'c1');
    expect(tx.pendingExpandForward, isTrue);
    expect(pipeline.delegate.adopted, isEmpty);
    expect(pipeline.delegate.expandForward, 0);
    expect(
      runtime.eventLog.events
          .where((e) => e.type == ReaderRuntimeEventType.windowRequested)
          .length,
      1,
    );

    runtime.onPointerReleased();
    runtime.onPhysicalScrollEnd();
    // 终端提交：committed 固化、事务结束、挂起收养/扩窗一次下发。
    expect(runtime.positionState.committed!.transactionId, tx.id);
    expect(runtime.transactions.current, isNull);
    expect(pipeline.settleAdopted, ['c1']);
    expect(pipeline.settleExpands, [true]);
    expect(
      runtime.eventLog.events.any(
        (e) => e.type == ReaderRuntimeEventType.transactionCompleted,
      ),
      isTrue,
    );
  });

  test('B3-2 去重持久化：阈值内帧不重复保存，越阈值帧再保存', () {
    final pipeline = _Pipeline();
    addTearDown(pipeline.dispose);

    pipeline.effect.offsetValue = 300;
    pipeline.feed();
    final first = pipeline.runtime.positionState.transient!.charOffset;
    expect(pipeline.delegate.persisted, [first]);

    // +5px 小步（映射比例 <2 字符/px，字符差 <48 且进度差 <0.004）：不重复保存。
    pipeline.effect.offsetValue = 305;
    pipeline.feed();
    final second = pipeline.runtime.positionState.transient!.charOffset;
    expect(second - first, lessThan(48));
    expect(pipeline.delegate.persisted, [first]);

    // +195px 大步（字符差 ≥48）：再次保存。
    pipeline.effect.offsetValue = 500;
    pipeline.feed();
    final third = pipeline.runtime.positionState.transient!.charOffset;
    expect(third - second, greaterThanOrEqualTo(48));
    expect(pipeline.delegate.persisted, [first, third]);
  });

  test('B3-3 收敛抑制：前向滚动中映射回退被丢弃，首帧与收敛解除后不抑制', () {
    final pipeline = _Pipeline();
    addTearDown(pipeline.dispose);
    pipeline.delegate.converging.add('c0');

    // 首帧（章节切换帧）：即便收敛中也不抑制，建立章节基线。
    pipeline.effect.offsetValue = 300;
    pipeline.feed();
    final baseline = pipeline.runtime.positionState.transient!.charOffset;
    expect(pipeline.delegate.persisted, [baseline]);
    expect(pipeline.delegate.trackerUpdates, 1);

    // 后台测高替换（2000→2600），前向小步滚动后映射回退：
    // 字符映射回退但 offset 前进 → 抑制回写。
    pipeline.rebuildWithHeight(2600);
    pipeline.effect.offsetValue = 305;
    pipeline.feed();
    final drifted = pipeline.runtime.positionState.transient!.charOffset;
    expect(drifted, lessThan(baseline));
    expect(pipeline.delegate.persisted, [baseline]);
    expect(pipeline.delegate.trackerUpdates, 1);
    expect(pipeline.runtime.lastResolvedOffset, 305);

    // 精测完成（收敛解除）：同一位置正常应用。
    pipeline.delegate.converging.remove('c0');
    pipeline.effect.offsetValue = 306;
    pipeline.feed();
    expect(pipeline.delegate.trackerUpdates, 2);
  });

  test('B3-4 零字符章：直达预取分支，不覆盖进度', () {
    final pipeline = _Pipeline();
    addTearDown(pipeline.dispose);
    pipeline.delegate.chapterProgress = 0.4;
    pipeline.delegate.totalChars['c0'] = 0;

    pipeline.effect.offsetValue = 300;
    pipeline.feed();

    expect(pipeline.delegate.preloadTail, 1);
    expect(pipeline.delegate.trackerUpdates, 0);
    expect(pipeline.delegate.persisted, isEmpty);
    expect(pipeline.delegate.chapterProgress, 0.4);
  });
}
