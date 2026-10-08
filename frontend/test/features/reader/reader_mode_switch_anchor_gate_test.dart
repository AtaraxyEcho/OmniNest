import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_page_builders.dart';

/// 模式切换锚点的释放规则回归闸门。
///
/// 锚点存活期间落地页的 onPageChanged 只是 `_syncPageView` 对齐物理页的
/// 回声；页首偏移比锚点更浅，一旦按它记账，切到翻页模式的位置就凭空回退
/// 到页首。此前单击（只切换工具栏可见性）也会消耗锚点，症状相同。
void main() {
  group('isModeSwitchLandingEcho', () {
    test('锚点存活时，落地页的回调判为回声', () {
      expect(
        isModeSwitchLandingEcho(
          anchorActive: true,
          changedPageIndex: 7,
          landedPageIndex: 7,
        ),
        isTrue,
      );
    });

    test('换到别的页面判为真实翻页，锚点可以释放', () {
      expect(
        isModeSwitchLandingEcho(
          anchorActive: true,
          changedPageIndex: 8,
          landedPageIndex: 7,
        ),
        isFalse,
      );
      expect(
        isModeSwitchLandingEcho(
          anchorActive: true,
          changedPageIndex: 6,
          landedPageIndex: 7,
        ),
        isFalse,
      );
    });

    test('无锚点时不参与判定，正常翻页照常记账', () {
      expect(
        isModeSwitchLandingEcho(
          anchorActive: false,
          changedPageIndex: 7,
          landedPageIndex: 7,
        ),
        isFalse,
      );
    });
  });
}
