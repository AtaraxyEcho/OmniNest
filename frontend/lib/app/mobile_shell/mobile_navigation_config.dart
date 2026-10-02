import 'package:omninest/features/backdrop/domain/app_backdrop_policy.dart';

/// 移动端一级导航与路由分支之间的稳定映射。
///
/// 一级信息架构固定为四个空间：Home（个人数字空间）、Library（媒体
/// 空间，聚合 Photos/Movies/Music）、Reader（专注空间）、Files（工作
/// 空间）。音乐/照片/影视不再作为一级入口，由 Library 直达或经模块
/// 全屏页承载。
class MobileNavigationConfig {
  const MobileNavigationConfig._();

  static const int portalBranch = 0;
  static const int libraryBranch = 1;
  static const int readerBranch = 2;
  static const int filesBranch = 3;

  /// 将四个持久化路由分支映射为四个一级导航项。
  static int destinationIndexForBranch(int branch) {
    return switch (branch) {
      >= portalBranch && <= filesBranch => branch,
      _ => portalBranch,
    };
  }

  /// 将四个一级导航项映射为对应的持久化路由分支。
  static int branchForDestination(int destination) {
    return switch (destination) {
      >= portalBranch && <= filesBranch => destination,
      _ => libraryBranch,
    };
  }

  /// 返回当前模块的全局搜索范围。
  static String searchScopeForBranch(int branch) {
    return switch (branch) {
      filesBranch => 'files',
      readerBranch => 'reader',
      _ => 'all',
    };
  }

  /// 返回当前分支默认使用的全局环境策略。
  ///
  /// 四个空间共享同一壁纸身份，按任务选择环境档位：Home 沉浸、
  /// Library 环境降存在感、Reader 静态专注、Files 近实底工具面。
  static AppBackdropPolicy backdropPolicyForBranch(int branch) {
    return switch (branch) {
      portalBranch => AppBackdropPolicy.portalMobile,
      libraryBranch => AppBackdropPolicy.ambientMedia,
      readerBranch => AppBackdropPolicy.focusReading,
      _ => AppBackdropPolicy.utilitySurface,
    };
  }
}
