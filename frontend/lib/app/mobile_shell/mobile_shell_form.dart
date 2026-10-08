import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/app/mobile_shell/mobile_shell_feature_bindings.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/mobile_app_theme.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/core/widgets/responsive_breakpoints.dart';

/// 判断当前平台和视口是否应启用统一移动端壳层。
///
/// 宽度自适应仅作用于手机浏览器（Web 且浏览器宿主 OS 为 Android/iOS）
/// 与桌面应用窄窗；桌面浏览器收缩窗口不切换移动壳层。
bool shouldUseResponsiveMobileShell({
  required bool mobilePlatform,
  required double width,
}) {
  return resolveMobileShell(
    mobilePlatform: mobilePlatform,
    web: kIsWeb,
    hostPlatform: defaultTargetPlatform,
    width: width,
  );
}

/// 模块全屏页「回门户」链接的目标：移动壳层回到 Library 媒体空间，
/// 桌面端维持回到 Portal 首页。
String modulePortalLinkTarget(BuildContext context) {
  return shouldUseResponsiveMobileShell(
        mobilePlatform: isMobilePlatform,
        width: MediaQuery.sizeOf(context).width,
      )
      ? '/library'
      : '/portal';
}

/// [shouldUseResponsiveMobileShell] 的纯函数形态，便于按宿主场景测试。
bool resolveMobileShell({
  required bool mobilePlatform,
  required bool web,
  required TargetPlatform hostPlatform,
  required double width,
}) {
  if (mobilePlatform) {
    return true;
  }
  final compact = ResponsiveBreakpoints.isCompact(width);
  if (web) {
    final mobileBrowser =
        hostPlatform == TargetPlatform.android ||
        hostPlatform == TargetPlatform.iOS;
    return mobileBrowser && compact;
  }
  return compact;
}

/// 推入路由是否继续强制暗色环境基底。
///
/// 壁纸在场时维持暗栈：环境可读性的极性由壁纸亮度决定（尚未实现），不跟随明暗设置。
/// 无壁纸的实底工具面随根主题，消除「壳强制暗、页内随主题」的分裂态。
bool shouldForceEnvironmentDark({
  required bool solidSurface,
  required bool backdropActive,
}) {
  return !solidSurface || backdropActive;
}

/// 根级推入路由的移动形态宿主包装。
///
/// 顶层的模块路由（/notifications 等）在 StatefulShellRoute 之外，天然
/// 拿不到壳层的 MobileShellScope；本包装在移动壳层启用时为路由内容补挂
/// scope，使页面可用 isHosted 分叉移动形态，并让页内工位弹窗经批次化
/// 分流走底部玻璃面板。桌面宽窗原样透传；测试直接 pump 页面组件时不经
/// 路由，scope 不存在，桌面路径不受影响。
class MobileHostedRoute extends ConsumerWidget {
  const MobileHostedRoute({
    required this.child,
    this.solidSurface = false,
    super.key,
  });

  final Widget child;

  /// 该路由是否为不依赖环境壁纸的实底工具面（工具目录、通知中心）。
  /// 媒体与阅读模块页保持环境档，不设此标记。
  final bool solidSurface;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = shouldUseResponsiveMobileShell(
      mobilePlatform: isMobilePlatform,
      width: MediaQuery.sizeOf(context).width,
    );
    if (!active) {
      return child;
    }
    // 根级推入页脱离壳层的暗色 Theme：环境档与壁纸在场时按壳层同规则兜底，
    // 浅色根主题下 scheme 派生色（分段控件/设置组/弹窗面板）不翻白；
    // 无壁纸的实底工具面随根主题，页内配色由 MobileEnvPalette 的浅实例提供。
    final baseTheme = Theme.of(context);
    final forceDark = shouldForceEnvironmentDark(
      solidSurface: solidSurface,
      backdropActive: ref.watch(mobileShellLocalBackdropActiveProvider),
    );
    final shellTheme =
        baseTheme.brightness == Brightness.dark
            ? baseTheme
            : forceDark
            ? OmniNestTheme.dark()
            : _withLightPolarity(MobileAppTheme.resolve(baseTheme));
    return Theme(
      data: shellTheme,
      child: MobileShellScope(hosted: true, child: child),
    );
  }
}

/// 追加浅色极性表。
///
/// `ThemeData.copyWith(extensions:)` 整体替换扩展集，因此必须带上既有扩展，
/// 否则实底页会丢掉模块调色板（Photos/Files/Reader 等）。
ThemeData _withLightPolarity(ThemeData theme) {
  return theme.copyWith(
    extensions: [...theme.extensions.values, MobileEnvPalette.light],
  );
}
