import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/theme/mobile_layout_tokens.dart';
import 'package:omninest/features/library/presentation/widgets/library_space_tier.dart';
import 'package:omninest/features/portal/presentation/widgets/portal_mobile_tier.dart';

/// 手机档页面留白的取值闸门。
///
/// 基准是样例的**主内容**档：`.content-scroll`、`.module-overlay > main`、
/// `.search-overlay main`、`.book-detail-scroll`、`.weather-sheet > main`
/// 全部是 `20px` 左右内缩；样例里的 `16px` 属于底部抽屉
///（`.glass-sheet`/`.account-sheet`/`.notif-settings` 的 `10px 16px`），不是页面。
/// 顶栏一直写死 20，所以这一档取 16 会让正文左缘比顶栏缩进 4px。
///
/// 这条闸门存在的原因：改这个值时两张 golden 都全绿，因为它们不覆盖
/// 这几页的左缘 —— 数值没有守门人就必须自己补一个，别拿"测试没红"当没影响。
void main() {
  test('手机档页面留白取样例主内容档 20', () {
    expect(
      MobileLayoutTokens.horizontalPadding,
      20,
      reason: '样例主内容是 20；16 是抽屉档，别拿它当页面档',
    );
  });

  test('门户与媒体库的手机档确实吃到该 token', () {
    final portal = PortalMobileTier.resolveWidth(411);
    expect(portal.homeHorizontalPadding, 20);
    expect(portal.contentHorizontalPadding, 20);
    expect(LibrarySpaceTier.resolveWidth(411).horizontalPadding, 20);
  });

  test('留白随档位单调抬升，改一档不会把上一档压回去', () {
    final phone = MobileLayoutTokens.horizontalPadding;
    final smallTablet = MobileLayoutTokens.tabletHorizontalPadding;
    final largeTabletHome =
        PortalMobileTier.resolveWidth(1040).homeHorizontalPadding;
    expect(phone, lessThan(smallTablet));
    expect(smallTablet, lessThan(largeTabletHome));
  });
}
