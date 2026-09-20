import 'package:flutter/material.dart';
import 'package:omninest/app/theme/mobile_app_theme.dart';
import 'package:omninest/app/mobile_shell/mobile_app_shell.dart';
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

  final String owner;
  final AppBackdropPolicy policy;

  /// 注册路由的完整路径，用于派生分支前缀；路径不可知时省略。
  final String? routePath;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final useMobileTheme = shouldUseResponsiveMobileShell(
      mobilePlatform: isMobilePlatform,
      width: MediaQuery.sizeOf(context).width,
    );
    Widget content = Builder(
      builder:
          (context) => ColoredBox(
            color:
                policy.visible
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
      policy: policy,
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
