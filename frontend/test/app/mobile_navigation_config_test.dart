import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/mobile_shell/mobile_navigation_config.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop_policy.dart';

void main() {
  group('MobileNavigationConfig', () {
    test('一级导航为四个空间：首页·媒体库·阅读·文件', () {
      expect(MobileNavigationConfig.portalBranch, 0);
      expect(MobileNavigationConfig.libraryBranch, 1);
      expect(MobileNavigationConfig.readerBranch, 2);
      expect(MobileNavigationConfig.filesBranch, 3);
    });

    test('分支与一级导航项双向映射保持一致', () {
      for (var index = 0; index < 4; index++) {
        expect(MobileNavigationConfig.destinationIndexForBranch(index), index);
        expect(MobileNavigationConfig.branchForDestination(index), index);
      }
      expect(
        MobileNavigationConfig.branchForDestination(99),
        MobileNavigationConfig.libraryBranch,
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
          MobileNavigationConfig.readerBranch,
        ),
        'reader',
      );
      expect(
        MobileNavigationConfig.searchScopeForBranch(
          MobileNavigationConfig.portalBranch,
        ),
        'all',
      );
    });

    test('四空间共享壁纸身份并按环境档位降存在感', () {
      expect(
        MobileNavigationConfig.backdropPolicyForBranch(
          MobileNavigationConfig.portalBranch,
        ),
        AppBackdropPolicy.portalMobile,
      );
      final libraryPolicy = MobileNavigationConfig.backdropPolicyForBranch(
        MobileNavigationConfig.libraryBranch,
      );
      expect(libraryPolicy, AppBackdropPolicy.ambientMedia);
      expect(libraryPolicy.visible, isTrue);
      expect(libraryPolicy.environmentMode, AppEnvironmentMode.ambient);
      final readerPolicy = MobileNavigationConfig.backdropPolicyForBranch(
        MobileNavigationConfig.readerBranch,
      );
      expect(readerPolicy.environmentMode, AppEnvironmentMode.focus);
      final filesPolicy = MobileNavigationConfig.backdropPolicyForBranch(
        MobileNavigationConfig.filesBranch,
      );
      expect(filesPolicy.environmentMode, AppEnvironmentMode.utility);
      expect(filesPolicy.visible, isTrue);
      // 环境档位全部静态化或连续化由档位决定，但一律可见（共享身份）。
      for (final branch in <int>[
        MobileNavigationConfig.libraryBranch,
        MobileNavigationConfig.readerBranch,
        MobileNavigationConfig.filesBranch,
      ]) {
        final policy = MobileNavigationConfig.backdropPolicyForBranch(branch);
        expect(policy.visible, isTrue);
        expect(policy.playbackMode, AppBackdropPlaybackMode.paused);
        expect(policy.motionAllowed, isFalse);
      }
    });
  });
}
