import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_position_target.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_restore_manager.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_runtime_identity.dart';

void main() {
  group('ReaderRestoreManager（B6 §7.1 返工：target/phase/isBusy）', () {
    test('begin 登记目标与身份，相位进入 applying，isBusy 为真', () {
      final manager = ReaderRestoreManager();
      const target = ReaderPositionTarget(chapterId: 'c1', charOffset: 10);
      final tookOver = manager.begin(
        target,
        identity: const ReaderRuntimeIdentity(
          itemId: 'item-1',
          readingMode: 'scroll',
        ),
      );
      expect(tookOver, isTrue);
      expect(manager.target, target);
      expect(manager.phase, ReaderRestorePhase.applying);
      expect(manager.isBusy, isTrue);
    });

    test('新 begin 清除旧目标（编排端凭 token 使旧帧失效）', () {
      final manager = ReaderRestoreManager();
      manager.begin(
        const ReaderPositionTarget(chapterId: 'c1', charOffset: 10),
      );
      manager.begin(
        const ReaderPositionTarget(chapterId: 'c1', charOffset: 20),
      );
      expect(
        manager.target,
        const ReaderPositionTarget(chapterId: 'c1', charOffset: 20),
      );
      expect(manager.phase, ReaderRestorePhase.applying);
    });

    test('cancel：applying/stabilizing 进入 cancelled 并清目标；终态不受影响', () {
      final manager = ReaderRestoreManager();
      manager.begin(const ReaderPositionTarget(chapterId: 'c1', charOffset: 0));
      manager.cancel();
      expect(manager.phase, ReaderRestorePhase.cancelled);
      expect(manager.target, isNull);
      expect(manager.isBusy, isFalse);

      // 终态后 cancel 保持原相位。
      manager.begin(const ReaderPositionTarget(chapterId: 'c1', charOffset: 0));
      manager.markCompleted();
      expect(manager.phase, ReaderRestorePhase.completed);
      manager.cancel();
      expect(manager.phase, ReaderRestorePhase.completed);

      // idle 时 cancel 无副作用。
      manager.cancel();
      expect(manager.phase, ReaderRestorePhase.completed);
    });

    test(
      '相位机：applying → stabilizing → completed，markStabilizing 只在 applying 生效',
      () {
        final manager = ReaderRestoreManager();
        manager.begin(
          const ReaderPositionTarget(chapterId: 'c1', charOffset: 5),
        );
        manager.markCompleted();
        expect(manager.phase, ReaderRestorePhase.completed);
        expect(manager.target, isNull);

        manager.begin(
          const ReaderPositionTarget(chapterId: 'c1', charOffset: 5),
        );
        manager.markStabilizing();
        expect(manager.phase, ReaderRestorePhase.stabilizing);
        expect(manager.isBusy, isTrue);
        // stabilizing 下重复 markStabilizing 不再变化。
        manager.markStabilizing();
        expect(manager.phase, ReaderRestorePhase.stabilizing);
        manager.markCompleted();
        expect(manager.phase, ReaderRestorePhase.completed);
      },
    );

    test('markTimedOut/markFailed 从任意相位进入终态并清目标（§97）', () {
      final manager = ReaderRestoreManager();
      manager.begin(const ReaderPositionTarget(chapterId: 'c1', charOffset: 5));
      manager.markTimedOut();
      expect(manager.phase, ReaderRestorePhase.timedOut);
      expect(manager.isBusy, isFalse);
      expect(manager.target, isNull);

      manager.begin(const ReaderPositionTarget(chapterId: 'c1', charOffset: 5));
      manager.markStabilizing();
      manager.markFailed();
      expect(manager.phase, ReaderRestorePhase.failed);
      expect(manager.target, isNull);
    });

    test('matchesIdentity：发起身份与回写时身份比对（§57 的 B6 载体）', () {
      final manager = ReaderRestoreManager();
      final scrollIdentity = const ReaderRuntimeIdentity(
        itemId: 'item-1',
        readingMode: 'scroll',
      );
      manager.begin(
        const ReaderPositionTarget(chapterId: 'c1', charOffset: 5),
        identity: scrollIdentity,
      );
      expect(manager.matchesIdentity(scrollIdentity), isTrue);
      expect(
        manager.matchesIdentity(
          const ReaderRuntimeIdentity(itemId: 'item-2', readingMode: 'scroll'),
        ),
        isFalse,
      );
      expect(
        manager.matchesIdentity(
          const ReaderRuntimeIdentity(itemId: 'item-1', readingMode: 'page'),
        ),
        isFalse,
      );
      // 未登记身份（页模式相位借用）时不拦截。
      manager.begin(const ReaderPositionTarget(chapterId: 'c1', charOffset: 6));
      expect(manager.matchesIdentity(null), isTrue);
    });
  });
}
