import 'package:omninest/features/backdrop/domain/app_backdrop_policy.dart';

/// 移动端一级导航与路由分支之间的稳定映射。
class MobileNavigationConfig {
  const MobileNavigationConfig._();

  static const int portalBranch = 0;
  static const int filesBranch = 5;
  static const int musicBranch = 1;
  static const int photosBranch = 2;
  static const int videoBranch = 3;
  static const int readerBranch = 4;

  /// 将六个持久化路由分支映射为六个一级导航项。
  static int destinationIndexForBranch(int branch) {
    return switch (branch) {
      >= portalBranch && <= filesBranch => branch,
      _ => portalBranch,
    };
  }

  /// 将六个一级导航项映射为对应的持久化路由分支。
  static int branchForDestination(int destination) {
    return switch (destination) {
      >= portalBranch && <= filesBranch => destination,
      _ => readerBranch,
    };
  }

  /// 返回当前模块的全局搜索范围。
  static String searchScopeForBranch(int branch) {
    return switch (branch) {
      filesBranch => 'files',
      musicBranch => 'music',
      photosBranch => 'photos',
      videoBranch => 'video',
      readerBranch => 'reader',
      _ => 'all',
    };
  }

  /// 返回当前分支默认使用的应用背景策略。
  ///
  /// 动态壁纸仅保留给首页与音乐（玻璃层）；照片、影视、阅读、文件为
  /// 实底内容模块，参考桌面端中心页行为隐藏壁纸并使用主题纯色。
  static AppBackdropPolicy backdropPolicyForBranch(int branch) {
    return switch (branch) {
      portalBranch => AppBackdropPolicy.portalMobile,
      musicBranch => AppBackdropPolicy.musicDeck,
      _ => AppBackdropPolicy.work,
    };
  }
}
