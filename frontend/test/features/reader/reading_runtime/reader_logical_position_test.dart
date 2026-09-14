import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_logical_position.dart';

void main() {
  group('ReaderLogicalPositionState（B8：跨模式位置记账权威）', () {
    test('初始态：空章身份与零偏移', () {
      final state = ReaderLogicalPositionState();
      expect(state.chapterId, '');
      expect(state.charOffset, 0);
      expect(state.current.charOffset, 0);
    });

    test('accept 成对记账：章身份与偏移同帧更新', () {
      final state = ReaderLogicalPositionState();
      state.accept(chapterId: 'c1', charOffset: 420);
      expect(state.chapterId, 'c1');
      expect(state.charOffset, 420);

      // 跨章推进：身份与偏移必须一起变（防旧章偏移算进新章）。
      state.accept(chapterId: 'c2', charOffset: 88);
      expect(state.chapterId, 'c2');
      expect(state.charOffset, 88);
    });

    test('重复记账同值幂等', () {
      final state = ReaderLogicalPositionState();
      state.accept(chapterId: 'c1', charOffset: 100);
      state.accept(chapterId: 'c1', charOffset: 100);
      expect(state.charOffset, 100);
    });

    test('charOffset 为 0 的记账合法（章首/封面章）', () {
      final state = ReaderLogicalPositionState();
      state.accept(chapterId: 'cover', charOffset: 0);
      expect(state.chapterId, 'cover');
      expect(state.charOffset, 0);
    });
  });
}
