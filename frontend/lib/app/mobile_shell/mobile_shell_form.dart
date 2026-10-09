import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/app/mobile_shell/mobile_environment_scope.dart';
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

/// 推入路由是否强制暗色环境基底。
///
/// 只有非实底（沉浸/透明）路由保持暗栈：它们的底色由环境层绘制，极性归空间自己。
/// 实底工具面自带底色，必须与壳层共用同一极性判定，否则出现
/// 「浅壳导航胶囊压着暗工具页」这类分裂态。
bool shouldForceEnvironmentDark({required bool solidSurface}) {
  return !solidSurface;
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
    // 根级推入页脱离壳层的暗色 Theme：实底面与壳层共用同一极性判定，
    // 非实底（沉浸）路由维持暗栈，底色由环境层绘制。
    final baseTheme = Theme.of(context);
    final forceDark = shouldForceEnvironmentDark(solidSurface: solidSurface);
    final envPalette =
        forceDark
            ? MobileEnvPalette.dark
            : watchMobileEnvPalette(ref, baseTheme);
    final shellTheme = (envPalette.brightness == Brightness.dark
            ? (baseTheme.brightness == Brightness.dark
                ? baseTheme
                : OmniNestTheme.dark())
            : MobileAppTheme.resolve(baseTheme))
        .withEnvPalette(envPalette);
    return Theme(
      data: shellTheme,
      child: MobileShellScope(hosted: true, child: child),
    );
  }
}
