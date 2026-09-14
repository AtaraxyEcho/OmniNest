import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_geometry_commit.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_layout_snapshot.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_position_resolver.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_transaction.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_transaction_manager.dart';

import 'geometry_fixtures.dart';

void main() {
  group('ReaderGeometryCommit（方案 §38-§40/§68/§107）', () {
    test('Commit 按视觉锚点重映射并给出修正 offset', () {
      // 旧布局图片高 600，新布局图片高 800；锚点固定在图片中部。
      final oldGeometry = snapshotFor([entryWithImage(id: 'c1')]);
      final newGeometry = snapshotFor([
        entryWithImage(id: 'c1', imageHeight: 800),
      ]);
      final layout = layoutFor(oldGeometry);
      final manager = ReaderTransactionManager();
      // contentY = 386 + 50 = 436 → 章体局部 400 = 图片(100..700)中部。
      final tx = manager.begin(
        kind: ReaderTransactionKind.userDrag,
        layout: layout,
        initialOffset: 386,
        initialVisualProgress: 0.5,
      );

      const commit = ReaderGeometryCommit();
      final result = commit.commit(transaction: tx, candidate: newGeometry);

      expect(tx.geometryCommitted, isTrue);
      expect(result.geometry.revision, newGeometry.revision);
      // 新布局图片中部 = 章头 36 + 文本 100 + 400 = 536 → offset 486。
      expect(result.correctedOffset, closeTo(486, 0.5));

      // 方案 §40：Commit 后必须用修正 offset 重新 Resolve；
      // 新快照的块内比例应保持锚点所见（图片中部 → ratio≈0.5）。
      final newLayout = ReaderLayoutSnapshot(
        geometry: newGeometry,
        viewport: layout.viewport,
        windowRevision: layout.windowRevision,
      );
      const resolver = ReaderPositionResolver();
      final reResolved =
          resolver.resolve(
            scrollOffset: result.correctedOffset!,
            layout: newLayout,
            transactionId: tx.id,
          )!;
      expect(reResolved.chapterId, 'c1');
      expect(reResolved.blockIndex, 1);
      expect(reResolved.blockRatio, closeTo(0.5, 0.001));
    });

    test('同一事务二次 Commit 抛 StateError（方案 §107）', () {
      final geometry = snapshotFor([
        textEntry(id: 'c1', heights: const [100, 200, 300]),
      ]);
      final manager = ReaderTransactionManager();
      final tx = manager.begin(
        kind: ReaderTransactionKind.wheel,
        layout: layoutFor(geometry),
        initialOffset: 0,
        initialVisualProgress: 0,
      );
      const commit = ReaderGeometryCommit();
      commit.commit(transaction: tx, candidate: geometry);
      expect(
        () => commit.commit(transaction: tx, candidate: geometry),
        throwsStateError,
      );
    });

    test('锚点章不在 Candidate 内时 correctedOffset 为 null', () {
      final oldGeometry = snapshotFor([
        textEntry(id: 'c1', heights: const [100, 200, 300]),
      ]);
      final candidate = snapshotFor([
        textEntry(id: 'c2', heights: const [100, 200, 300]),
      ]);
      final manager = ReaderTransactionManager();
      final tx = manager.begin(
        kind: ReaderTransactionKind.restore,
        layout: layoutFor(oldGeometry),
        initialOffset: 100,
        initialVisualProgress: 0,
      );
      const commit = ReaderGeometryCommit();
      final result = commit.commit(transaction: tx, candidate: candidate);
      expect(result.correctedOffset, isNull);
    });
  });
}
