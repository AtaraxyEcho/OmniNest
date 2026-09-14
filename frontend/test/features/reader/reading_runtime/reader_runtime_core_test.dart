import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/application/reader_progress_snapshot.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_geometry_scheduler.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_layout_revision.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_operation_token.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_persistence_queue.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_position_snapshot.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_position_state.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_runtime_identity.dart';

ReaderProgressSnapshot _progressSnapshot(String chapterId, int charOffset) {
  return ReaderProgressSnapshot(
    chapterId: chapterId,
    charOffset: charOffset,
    progress: 0.5,
    chapterProgress: 0.5,
    mode: 'scroll',
    updatedAt: DateTime(2026),
  );
}

ReaderPositionSnapshot _positionSnapshot(int charOffset) {
  return ReaderPositionSnapshot(
    transactionId: 1,
    layoutRevision: const ReaderLayoutRevision(
      geometryRevision: 1,
      windowRevision: 0,
    ),
    scrollOffset: charOffset.toDouble(),
    contentY: charOffset.toDouble(),
    chapterId: 'c1',
    blockIndex: 0,
    blockRatio: 0,
    charOffset: charOffset,
    chapterVisualCursor: charOffset.toDouble(),
  );
}

void main() {
  group('ReaderOperationToken（新方案 §35/§43）', () {
    test('签发与校验：invalidate 使在途令牌全部失效', () {
      final token = ReaderOperationToken();
      final g1 = token.issue();
      expect(token.isCurrent(g1), isTrue);

      token.invalidate();
      expect(token.isCurrent(g1), isFalse);

      final g2 = token.issue();
      expect(token.isCurrent(g2), isTrue);
      expect(g2, isNot(g1));
    });
  });

  group('ReaderPositionState（新方案 §29/§30）', () {
    test('transient 随解析更新，committed 仅在提交后前进', () {
      final state = ReaderPositionState();
      expect(state.transient, isNull);
      expect(state.committed, isNull);

      state.acceptTransient(_positionSnapshot(10));
      expect(state.transient!.charOffset, 10);
      // 未提交前持久化视角仍为空。
      expect(state.committed, isNull);

      state.acceptTransient(_positionSnapshot(20));
      expect(state.transient!.charOffset, 20);

      final committed = state.commitTransient()!;
      expect(committed.charOffset, 20);
      expect(state.committed!.charOffset, 20);

      // 提交后 transient 继续前进不影响 committed。
      state.acceptTransient(_positionSnapshot(30));
      expect(state.transient!.charOffset, 30);
      expect(state.committed!.charOffset, 20);
    });
  });

  group('ReaderGeometryScheduler（B5 §49 装载边界）', () {
    test('手势期间挂起拒绝，终端边界放行，挂起随终端消费清零', () {
      final scheduler = ReaderGeometryScheduler();
      expect(scheduler.authorizeInstall(inActiveGesture: true), isFalse);
      expect(scheduler.hasPendingCommit, isTrue);

      // 终端边界（settle 旁路）总是放行，取最新状态装载。
      expect(
        scheduler.authorizeInstall(inActiveGesture: true, terminal: true),
        isTrue,
      );
      // 手势期间挂起过一次：终端消费挂起标记。
      expect(scheduler.consumePendingCommit(), isTrue);
      expect(scheduler.hasPendingCommit, isFalse);
      expect(scheduler.consumePendingCommit(), isFalse);
      // 空闲边界直接放行。
      expect(scheduler.authorizeInstall(inActiveGesture: false), isTrue);
    });
  });

  group('ReaderPersistenceQueue（新方案 §28/§30）', () {
    test('相邻同位置去重，变化即入队', () {
      final enqueued = <ReaderProgressSnapshot>[];
      final queue = ReaderPersistenceQueue(onEnqueue: enqueued.add);

      queue.enqueue(_progressSnapshot('c1', 10));
      queue.enqueue(_progressSnapshot('c1', 10));
      expect(enqueued.length, 1);

      queue.enqueue(_progressSnapshot('c1', 80));
      queue.enqueue(_progressSnapshot('c2', 5));
      expect(enqueued.length, 3);
      expect(enqueued.map((s) => s.charOffset), [10, 80, 5]);
      expect(queue.last!.chapterId, 'c2');
    });
  });

  group('ReaderRuntimeIdentity（新方案 §57）', () {
    test('同值相等，异值不等', () {
      const a = ReaderRuntimeIdentity(itemId: 'i1', readingMode: 'scroll');
      const b = ReaderRuntimeIdentity(itemId: 'i1', readingMode: 'scroll');
      const c = ReaderRuntimeIdentity(itemId: 'i1', readingMode: 'page');
      expect(a, b);
      expect(a, isNot(c));
    });
  });
}
