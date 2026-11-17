import 'package:flutter/material.dart';
import 'package:omninest/app/mobile_shell/mobile_shell_form.dart';
import 'package:omninest/app/theme/mobile_app_theme.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop_policy.dart';
import 'package:omninest/features/backdrop/presentation/app_backdrop_scene_scope.dart';

class AppRouteSurface extends StatelessWidget {
  const AppRouteSurface({
    required this.owner,
    required this.policy,
    required this.child,
    this.routePath,
    super.key,
  });

  /// 环境自适应路由表面：背景策略在构建期按宿主形态选择。
  ///
  /// 移动壳层继承全局环境模式；桌面端维持原有静态快照/实底语义。
  factory AppRouteSurface.environmental({
    required String owner,
    required String routePath,
    required Widget child,
    Key? key,
  }) {
    return AppRouteSurface._environmental(
      key: key,
      owner: owner,
      routePath: routePath,
      child: child,
    );
  }

  const AppRouteSurface._environmental({
    required this.owner,
    required this.routePath,
    required this.child,
    super.key,
  }) : policy = null;

  final String owner;

  /// 显式背景策略；环境自适应模式下为 null，构建期由路由表推导。
  final AppBackdropPolicy? policy;

  /// 注册路由的完整路径，用于派生分支前缀；路径不可知时省略。
  final String? routePath;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final useMobileTheme = shouldUseResponsiveMobileShell(
      mobilePlatform: isMobilePlatform,
      width: MediaQuery.sizeOf(context).width,
    );
    final effectivePolicy =
        policy ??
        routeBackdropPolicy(routePath ?? '', mobileShell: useMobileTheme);
    // 表面色必须在下面的 Theme 覆盖之内解析，所以由子组件自己读 Theme.of。
    Widget content = RouteEnvironmentSurface(
      environmentVisible: effectivePolicy.visible,
      child: child,
    );
    if (useMobileTheme) {
      content = Theme(
        data: MobileAppTheme.resolve(Theme.of(context)),
        child: content,
      );
    }
    final pathPrefix = _branchPrefixOf(routePath);
    return AppBackdropSceneScope(
      owner: owner,
      policy: effectivePolicy,
      pathPrefix: pathPrefix,
      child: content,
    );
  }

  /// 取路径首段作为分支前缀（`/photos/albums/1` → `/photos`）。
  static String? _branchPrefixOf(String? path) {
    if (path == null || !path.startsWith('/')) {
      return null;
    }
    final firstSlash = path.indexOf('/', 1);
    return firstSlash < 0 ? path : path.substring(0, firstSlash);
  }
}

/// 路由内容底：策略要求"环境可见"时留透明，但整段进出动画里必须遮住
/// 仍在绘制的下一页。
///
/// 导航栈要到动画结束才把下一页置为 offstage，透明表面因此会把上一页——
/// 以及同一帧里正在下滑关闭的模态面板——从新页面底下透出来，视觉上就是
/// 双重曝光。样例本身是单页 SPA，切换时上下页从不同时在场，所以这里垫一层
/// 实底：两页重合的前大半程保持全厚，只剩窄缝时才线性放开，落位后完全撤除，
/// 壁纸照常透上来。
class RouteEnvironmentSurface extends StatelessWidget {
  const RouteEnvironmentSurface({
    required this.environmentVisible,
    required this.child,
    super.key,
  });

  /// 背景策略是否要求让环境层透上来。
  final bool environmentVisible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final surfaceColor = Theme.of(context).colorScheme.surface;
    if (!environmentVisible) {
      return ColoredBox(color: surfaceColor, child: child);
    }
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null) {
      return ColoredBox(color: Colors.transparent, child: child);
    }
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final cover = environmentCoverageAt(animation.status, animation.value);
        return Stack(
          fit: StackFit.expand,
          children: [
            if (cover > 0)
              Positioned.fill(
                child: ColoredBox(color: surfaceColor.withValues(alpha: cover)),
              ),
            child,
          ],
        );
      },
    );
  }
}

/// 遮蔽开始线性放开的行程比例。
///
/// 入场与退场都是"刚离开静止位的那大半程"与下一页重合最多，所以遮蔽先保持
/// 全厚，只剩窄缝时才放开；撑到最后一帧才撤会硬切成壁纸底。
const double _coverageReleaseTravel = 0.6;

/// 进/出动画需要多厚的实底来压住仍在绘制的下一页；已落位的页面不画这层。
///
/// 行程按方向换算：入场 value 由 0 涨到 1，退场由 1 降到 0，两个方向的
/// "离开静止位"分别对应 value 与 1-value。
@visibleForTesting
double environmentCoverageAt(AnimationStatus status, double value) {
  if (status == AnimationStatus.completed) {
    return 0;
  }
  final travel = status == AnimationStatus.reverse ? 1 - value : value;
  if (travel <= _coverageReleaseTravel) {
    return 1;
  }
  return ((1 - travel) / (1 - _coverageReleaseTravel))
      .clamp(0.0, 1.0)
      .toDouble();
}

/// 推入路由的背景策略表。
///
/// 移动壳层按全局环境模式继承：媒体路由 ambient、阅读路由 focus、
/// 系统与工具路由 utility；桌面端保持原有语义（影视/系统实底、
/// 照片与阅读静态快照），避免移动端空间重构波及桌面基线。
AppBackdropPolicy routeBackdropPolicy(
  String path, {
  required bool mobileShell,
}) {
  final isMedia =
      path.startsWith('/photos') ||
      path.startsWith('/shared/photos') ||
      path.startsWith('/video') ||
      path.startsWith('/music');
  final isReader = path.startsWith('/reader');
  if (mobileShell) {
    if (isMedia) {
      return AppBackdropPolicy.ambientMedia;
    }
    if (isReader) {
      return AppBackdropPolicy.focusReading;
    }
    return AppBackdropPolicy.utilitySurface;
  }
  if (isMedia && !path.startsWith('/video') && !path.startsWith('/music')) {
    return AppBackdropPolicy.staticContent;
  }
  if (isReader) {
    return AppBackdropPolicy.staticContent;
  }
  return AppBackdropPolicy.work;
}
