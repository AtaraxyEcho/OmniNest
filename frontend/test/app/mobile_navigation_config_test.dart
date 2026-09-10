import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/mobile_shell/mobile_navigation_config.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop_policy.dart';

void main() {
  group('MobileNavigationConfig', () {
    test('导航顺序为 首页·音乐·照片·媒体·阅读·文件', () {
      expect(MobileNavigationConfig.portalBranch, 0);
      expect(MobileNavigationConfig.musicBranch, 1);
      expect(MobileNavigationConfig.photosBranch, 2);
      expect(MobileNavigationConfig.videoBranch, 3);
      expect(MobileNavigationConfig.readerBranch, 4);
      expect(MobileNavigationConfig.filesBranch, 5);
    });

    test('分支与一级导航项双向映射保持一致', () {
      for (var index = 0; index < 6; index++) {
        expect(MobileNavigationConfig.destinationIndexForBranch(index), index);
        expect(MobileNavigationConfig.branchForDestination(index), index);
      }
      expect(
        MobileNavigationConfig.branchForDestination(99),
        MobileNavigationConfig.readerBranch,
      );
    });

    test('模块搜索范围保持独立', () {
      expect(
        MobileNavigationConfig.searchScopeForBranch(
          MobileNavigationConfig.filesBranch,
        ),
        'files',
      );
      expect(
        MobileNavigationConfig.searchScopeForBranch(
          MobileNavigationConfig.videoBranch,
        ),
        'video',
      );
      expect(
        MobileNavigationConfig.searchScopeForBranch(
          MobileNavigationConfig.portalBranch,
        ),
        'all',
      );
    });

    test('动态壁纸仅保留给首页与音乐，内容模块隐藏壁纸', () {
      expect(
        MobileNavigationConfig.backdropPolicyForBranch(
          MobileNavigationConfig.portalBranch,
        ),
        AppBackdropPolicy.portalMobile,
      );
      expect(
        MobileNavigationConfig.backdropPolicyForBranch(
          MobileNavigationConfig.musicBranch,
        ),
        AppBackdropPolicy.musicDeck,
      );
      for (final branch in <int>[
        MobileNavigationConfig.filesBranch,
        MobileNavigationConfig.photosBranch,
        MobileNavigationConfig.videoBranch,
        MobileNavigationConfig.readerBranch,
      ]) {
        final policy = MobileNavigationConfig.backdropPolicyForBranch(branch);
        expect(policy, AppBackdropPolicy.work);
        expect(policy.visible, isFalse);
        expect(policy.playbackMode, AppBackdropPlaybackMode.paused);
        expect(policy.motionAllowed, isFalse);
      }
    });
  });
}
