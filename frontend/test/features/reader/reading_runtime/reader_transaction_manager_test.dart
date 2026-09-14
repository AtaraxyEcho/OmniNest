import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_transaction.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_transaction_manager.dart';

import 'geometry_fixtures.dart';

void main() {
  group('ReaderTransactionManager（方案 §23-§26）', () {
    test('已有 active 事务时 begin 直接失败（方案 §24）', () {
      final manager = ReaderTransactionManager();
      final layout = layoutFor(
        snapshotFor([
          textEntry(id: 'c1', heights: const [100, 200, 300]),
        ]),
      );
      manager.begin(
        kind: ReaderTransactionKind.userDrag,
        layout: layout,
        initialOffset: 0,
        initialVisualProgress: 0,
      );
      expect(
        () => manager.begin(
          kind: ReaderTransactionKind.wheel,
          layout: layout,
          initialOffset: 0,
          initialVisualProgress: 0,
        ),
        throwsStateError,
      );
      expect(manager.hasActive, isTrue);
    });

    test('beginOrReplace 原子切换：旧事务同步进入 cancelled（方案 §25）', () {
      final manager = ReaderTransactionManager();
      final layout = layoutFor(
        snapshotFor([
          textEntry(id: 'c1', heights: const [100, 200, 300]),
        ]),
      );
      final first = manager.begin(
        kind: ReaderTransactionKind.restore,
        layout: layout,
        initialOffset: 10,
        initialVisualProgress: 0,
      );
      final second = manager.beginOrReplace(
        kind: ReaderTransactionKind.userDrag,
        layout: layout,
        initialOffset: 12,
        initialVisualProgress: 0,
      );
      expect(first.phase, ReaderTransactionPhase.cancelled);
      expect(manager.current!.id, second.id);
      expect(second.lastScrollOffset, 12);
      expect(manager.isCurrent(first.id), isFalse);
      expect(manager.isCurrent(second.id), isTrue);
    });

    test('finish 仅对当前事务生效；完成后事务从管理器移除', () {
      final manager = ReaderTransactionManager();
      final layout = layoutFor(
        snapshotFor([
          textEntry(id: 'c1', heights: const [100, 200, 300]),
        ]),
      );
      final tx = manager.begin(
        kind: ReaderTransactionKind.wheel,
        layout: layout,
        initialOffset: 0,
        initialVisualProgress: 0,
      );
      manager.finish(tx.id + 100);
      expect(manager.hasActive, isTrue);
      manager.finish(tx.id);
      expect(tx.phase, ReaderTransactionPhase.completed);
      expect(manager.hasActive, isFalse);
      expect(manager.isCurrent(tx.id), isFalse);
    });

    test('cancelCurrent 将当前事务标记 cancelled（方案 §59）', () {
      final manager = ReaderTransactionManager();
      final layout = layoutFor(
        snapshotFor([
          textEntry(id: 'c1', heights: const [100, 200, 300]),
        ]),
      );
      final tx = manager.begin(
        kind: ReaderTransactionKind.sideTap,
        layout: layout,
        initialOffset: 0,
        initialVisualProgress: 0,
      );
      manager.cancelCurrent();
      expect(tx.phase, ReaderTransactionPhase.cancelled);
      expect(manager.hasActive, isFalse);
    });
  });
}
