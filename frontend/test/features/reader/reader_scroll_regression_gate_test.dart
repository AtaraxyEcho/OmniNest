import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_page_interaction_mixin.dart';

/// 滚动回退闸门的判定契约。
///
/// 闸门存在的理由是布局未收敛时的 charOffset 读数不可信（惯性/程序滚动），
/// 不是"用户不能往回读"。指针驱动的向后滚动是事实位置，必须继续追踪与持久化，
/// 否则进度与退出上报会停在最远处，重开时跳过用户回读的位置。
void main() {
  group('shouldDeferScrollProgress', () {
    test('指针驱动的深度回退不抑制', () {
      expect(
        shouldDeferScrollProgress(
          charOffset: 400,
          savedCharOffset: 9000,
          restoreTargetCharOffset: 9000,
          pointerDriven: true,
        ),
        isFalse,
      );
    });

    test('非指针的恢复目标深度偏离仍抑制', () {
      expect(
        shouldDeferScrollProgress(
          charOffset: 100,
          savedCharOffset: 0,
          restoreTargetCharOffset: 9000,
          pointerDriven: false,
        ),
        isTrue,
      );
    });

    test('非指针的已保存位置深度回退仍抑制', () {
      expect(
        shouldDeferScrollProgress(
          charOffset: 100,
          savedCharOffset: 9000,
          restoreTargetCharOffset: 0,
          pointerDriven: false,
        ),
        isTrue,
      );
    });

    test('回退未超过一半时不抑制', () {
      expect(
        shouldDeferScrollProgress(
          charOffset: 8000,
          savedCharOffset: 9000,
          restoreTargetCharOffset: 9000,
          pointerDriven: false,
        ),
        isFalse,
      );
    });

    test('恢复目标已复位时不再受旧目标约束', () {
      expect(
        shouldDeferScrollProgress(
          charOffset: 300,
          savedCharOffset: 300,
          restoreTargetCharOffset: 0,
          pointerDriven: false,
        ),
        isFalse,
      );
    });

    test('章首归零不被当作回退抑制', () {
      expect(
        shouldDeferScrollProgress(
          charOffset: 0,
          savedCharOffset: 9000,
          restoreTargetCharOffset: 0,
          pointerDriven: false,
        ),
        isFalse,
      );
    });
  });
}
