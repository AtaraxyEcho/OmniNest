import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_page_mixin.dart';

/// 同章远端进度被方向性守卫丢弃后，是否值得给用户一次手动跳转机会。
///
/// 守卫本身不能放开：不区分方向就会把本机刚保存的位置经服务端回灌重新施加，
/// 表现为滚动后内容回跳。提示是这条保守规则的补偿通道，但必须只对
/// 「不是自己回声、且确实带位置」的快照出现。
void main() {
  group('shouldOfferProgressJumpCue', () {
    test('非自身回声且带偏移时提示', () {
      expect(
        shouldOfferProgressJumpCue(isOwnEcho: false, snapshotCharOffset: 4200),
        isTrue,
      );
    });

    test('自身回声不提示', () {
      // 本机刚写入的位置经 provider 回灌，提示语会谎称"其他设备"，
      // 并且每轮滚动都可能再弹一次。
      expect(
        shouldOfferProgressJumpCue(isOwnEcho: true, snapshotCharOffset: 4200),
        isFalse,
      );
    });

    test('章首降级副本没有可跳转的偏移，不提示', () {
      expect(
        shouldOfferProgressJumpCue(isOwnEcho: false, snapshotCharOffset: 0),
        isFalse,
      );
    });
  });
}
