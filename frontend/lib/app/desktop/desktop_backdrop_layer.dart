import 'package:material_ui/material_ui.dart';
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
/// 切出壁纸作用域时通过 `Offstage` 保活，并将 `player.pause()` 延后 1 帧到
/// `addPostFrameCallback` 执行，避免与切页首帧 D3D11 光栅化抢锁。
class DesktopBackdropLayer extends ConsumerStatefulWidget {
  const DesktopBackdropLayer({required this.path, super.key});

  /// 当前工作区路径，用于判定「首页与音乐」范围。
  final String path;

  @override
  ConsumerState<DesktopBackdropLayer> createState() =>
      _DesktopBackdropLayerState();
}

class _DesktopBackdropLayerState extends ConsumerState<DesktopBackdropLayer> {
  bool? _effectiveActive;
  int _pauseScheduleSeq = 0;

  void _syncActiveState(bool desiredActive) {
    final current = _effectiveActive;
    if (current == null) {
      _effectiveActive = desiredActive;
      return;
    }
    if (desiredActive) {
      // 切入壁纸作用域时立即恢复活跃，同时作废此前排队的延后暂停回调。
      _pauseScheduleSeq++;
      _effectiveActive = true;
      return;
    }
    if (current) {
      // 切出壁纸作用域时延后 1 帧再把 active 置 false（触发 player.pause()），
      // 避免与新页面首帧 D3D11 光栅化争抢渲染线程锁。
      final seq = ++_pauseScheduleSeq;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || seq != _pauseScheduleSeq) {
          return;
        }
        if (_effectiveActive != false) {
          setState(() => _effectiveActive = false);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appBackdropControllerProvider).asData?.value;
    if (state == null || !state.hasActiveBackdrop) {
      _pauseScheduleSeq++;
      _effectiveActive = false;
      return const SizedBox.shrink();
    }
    final asset = state.selectedBackdrop;
    if (asset == null) {
      _pauseScheduleSeq++;
      _effectiveActive = false;
      return const SizedBox.shrink();
    }
    final inScope = desktopBackdropAppliesToRoute(
      ref.watch(desktopBackdropScopeProvider),
      widget.path,
    );
    final motionAllowed =
        !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    final desiredActive = inScope && motionAllowed;
    _syncActiveState(desiredActive);

    // 切出壁纸作用域时不再返回空盒子：那样会把 AppBackdropSurface 连同
    // media_kit 的视频纹理整棵树卸载，点回首页再从零挂载，跨栏那一下的
    // 顿挫就来自这里。改由 Offstage 保活（0 绘制、0 命中），外层包裹
    // ExcludeSemantics 防止装饰壁纸节点污染 Windows AXTree。
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
            active: _effectiveActive ?? desiredActive,
          ),
        ),
      ),
    );
  }
}
