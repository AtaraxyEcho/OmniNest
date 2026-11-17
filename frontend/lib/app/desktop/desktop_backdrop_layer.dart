import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omninest/app/desktop/desktop_backdrop_scope.dart';
import 'package:omninest/app/desktop/desktop_routes.dart';
import 'package:omninest/features/backdrop/backdrop_ui.dart';

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
    if (!_inScope(ref.watch(desktopBackdropScopeProvider))) {
      return const SizedBox.shrink();
    }
    final motionAllowed =
        !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    return KeyedSubtree(
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
        active: motionAllowed,
      ),
    );
  }

  bool _inScope(DesktopBackdropScope scope) {
    if (scope == DesktopBackdropScope.everywhere) {
      return true;
    }
    return path == DesktopRoutes.home ||
        path.startsWith('${DesktopRoutes.music}/') ||
        path == DesktopRoutes.music;
  }
}
