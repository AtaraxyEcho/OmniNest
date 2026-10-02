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
    Widget content = Builder(
      builder:
          (context) => ColoredBox(
            color:
                effectivePolicy.visible
                    ? Colors.transparent
                    : Theme.of(context).colorScheme.surface,
            child: child,
          ),
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
