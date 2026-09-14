import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_position_target.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_restore_manager.dart';

import 'geometry_fixtures.dart';

void main() {
  group('ReaderRestoreManager（方案 §55-§59/§120）', () {
    test('begin 建立 generation；新恢复使旧恢复全部失效（方案 §120）', () {
      final manager = ReaderRestoreManager();
      final layout = layoutFor(
        snapshotFor([
          textEntry(id: 'c1', heights: const [100, 200, 300]),
        ]),
      );
      final first = manager.begin(
        target: const ReaderPositionTarget(chapterId: 'c1', charOffset: 10),
        layout: layout,
        itemId: 'item-1',
        readingMode: 'scroll',
      );
      expect(manager.isCurrent(first.generation), isTrue);
      expect(manager.current, same(first));

      final second = manager.begin(
        target: const ReaderPositionTarget(chapterId: 'c1', charOffset: 20),
        layout: layout,
        itemId: 'item-1',
        readingMode: 'scroll',
      );
      expect(manager.isCurrent(first.generation), isFalse);
      expect(manager.isCurrent(second.generation), isTrue);
    });

    test('cancel 使在途回调失效（方案 §59）', () {
      final manager = ReaderRestoreManager();
      final layout = layoutFor(
        snapshotFor([
          textEntry(id: 'c1', heights: const [100, 200, 300]),
        ]),
      );
      final tx = manager.begin(
        target: const ReaderPositionTarget(chapterId: 'c1', charOffset: 0),
        layout: layout,
        itemId: 'item-1',
        readingMode: 'scroll',
      );
      manager.cancel();
      expect(manager.isCurrent(tx.generation), isFalse);
      expect(
        manager.isCallbackValid(tx, itemId: 'item-1', readingMode: 'scroll'),
        isFalse,
      );
      expect(manager.current, isNull);
    });

    test('回调校验包含 item/mode 三层身份（方案 §57/§121）', () {
      final manager = ReaderRestoreManager();
      final layout = layoutFor(
        snapshotFor([
          textEntry(id: 'c1', heights: const [100, 200, 300]),
        ]),
      );
      final tx = manager.begin(
        target: const ReaderPositionTarget(chapterId: 'c1', charOffset: 5),
        layout: layout,
        itemId: 'item-1',
        readingMode: 'scroll',
      );
      expect(
        manager.isCallbackValid(tx, itemId: 'item-1', readingMode: 'scroll'),
        isTrue,
      );
      expect(
        manager.isCallbackValid(tx, itemId: 'item-2', readingMode: 'scroll'),
        isFalse,
      );
      expect(
        manager.isCallbackValid(tx, itemId: 'item-1', readingMode: 'page'),
        isFalse,
      );
    });

    test('目标统一为 ReaderPositionTarget（方案 §19/§96）', () {
      final manager = ReaderRestoreManager();
      final layout = layoutFor(
        snapshotFor([
          textEntry(id: 'c1', heights: const [100, 200, 300]),
        ]),
      );
      const target = ReaderPositionTarget(chapterId: 'c1', charOffset: 42);
      final tx = manager.begin(
        target: target,
        layout: layout,
        itemId: 'item-1',
        readingMode: 'scroll',
      );
      expect(tx.target, target);
      expect(tx.layout, same(layout));
    });
  });
}
