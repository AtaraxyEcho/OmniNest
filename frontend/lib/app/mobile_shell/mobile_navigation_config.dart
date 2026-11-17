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

  /// 返回当前分支默认使用的全局环境策略。
  ///
  /// 四个空间共享同一壁纸身份，按任务选择环境档位：Home 沉浸、
  /// Library 环境降存在感、Reader 静态专注、Files 近实底工具面。
  static AppBackdropPolicy backdropPolicyForBranch(int branch) {
    return switch (branch) {
      portalBranch => AppBackdropPolicy.portalMobile,
      libraryBranch => AppBackdropPolicy.ambientMedia,
      readerBranch => AppBackdropPolicy.focusReading,
      filesBranch => AppBackdropPolicy.utilitySurface,
      _ => undeclaredBranch(
        branch,
        'backdropPolicyForBranch',
        AppBackdropPolicy.utilitySurface,
      ),
    };
  }

  /// 未登记的分支编号：调试构建当场抛错，发布构建按调用点给定的兜底值继续。
  ///
  /// 壳层按分支做的三类决策（顶栏与底部 tab 让位、多选占用、背景策略）都要求
  /// 逐条分支显式表态。新增一级分支却漏登记时，静默取兜底值不会有任何报错，
  /// 表现是「自带页头的整屏层叠在壳层顶栏下、出现两套页头」这类看得见却查不出
  /// 的错配，因此把默认路径改成调试期硬失败。
  static T undeclaredBranch<T>(int branch, String decision, T fallback) {
    assert(() {
      throw StateError(
        '分支 $branch 未在 $decision 声明策略：新增移动一级分支时必须逐条'
        '表态（兜底值 $fallback 只在发布构建生效）。',
      );
    }());
    return fallback;
  }
}
