import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omninest/app/desktop/desktop_backdrop_scope.dart';
import 'package:omninest/app/desktop/desktop_routes.dart';
import 'package:omninest/features/backdrop/backdrop_ui.dart';

/// 统一桌面壁纸范围判断，让常规工作区与沉浸路由切换到壁纸时使用同一条路由规则。
bool desktopBackdropAppliesToRoute(DesktopBackdropScope scope, String path) {
  if (scope == DesktopBackdropScope.everywhere) {
    return true;
  }
  final routePath = Uri.tryParse(path)?.path ?? path.split('?').first;
  return routePath == DesktopRoutes.home ||
      routePath.startsWith('${DesktopRoutes.music}/') ||
      routePath == DesktopRoutes.music;
}

/// 判断指定页面是否实际绘制壁纸，以便页面底色让出壁纸层。
bool desktopBackdropVisibleForRoute(WidgetRef ref, String path) {
  final configured = ref.watch(
    appBackdropControllerProvider.select(
      (async) => async.asData?.value.hasActiveBackdrop ?? false,
    ),
  );
  if (!configured) {
    return false;
  }
  return desktopBackdropAppliesToRoute(
    ref.watch(desktopBackdropScopeProvider),
    path,
  );
}

/// 桌面工作区的壁纸层（样例 `BackdropView.tsx` 的 `BackdropLayer`）。
///
/// 只在「已启用 + 选中素材可访问 + 当前页面在作用范围内」时铺满窗口；
/// 否则返回空盒子，让环境光接管。策略取 `work` 场景与 `content` 可读性档：
/// 桌面是长文与表格的主场，壁纸必须给前景让路。
class DesktopBackdropLayer extends ConsumerWidget {
  const DesktopBackdropLayer({required this.path, super.key});

  /// 当前工作区路径，用于判定「首页与音乐」范围。
  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appBackdropControllerProvider).asData?.value;
    if (state == null || !state.hasActiveBackdrop) {
      return const SizedBox.shrink();
    }
    final asset = state.selectedBackdrop;
    if (asset == null) {
      return const SizedBox.shrink();
    }
    final inScope = desktopBackdropAppliesToRoute(
      ref.watch(desktopBackdropScopeProvider),
      path,
    );
    final motionAllowed =
        !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    // 切出壁纸作用域时不再返回空盒子：那样会把 AppBackdropSurface 连同
    // media_kit 的视频纹理整棵树卸载，点回首页再从零挂载，跨栏那一下的
    // 顿挫就来自这里。改由 Offstage 保活（0 绘制、0 命中），并把 active
    // 置 false 让会话立即暂停解码；外层包裹 ExcludeSemantics 防止装饰壁纸
    // 节点污染 Windows AXTree。
    return ExcludeSemantics(
      child: Offstage(
        offstage: !inScope,
        child: KeyedSubtree(
          key: const ValueKey('desktop-backdrop'),
          child: AppBackdropSurface(
            asset: asset,
            settings: state.settings,
            policy: AppBackdropPolicy(
              scene: AppBackdropScene.work,
              visible: true,
              playbackMode: AppBackdropPlaybackMode.continuous,
              readabilityMode: AppBackdropReadabilityMode.content,
              motionAllowed: motionAllowed,
            ),
            // 桌面给 0：环境档的 sigma 是移动壳层语义，压到实底前景页上会沿
            // 边界出现对角亮缝（`app_backdrop_surface.dart` 的既有结论）。
            environmentBlurSigma: 0,
            active: inScope && motionAllowed,
          ),
        ),
      ),
    );
  }
}
