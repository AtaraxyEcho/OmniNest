import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/mobile_shell/mobile_shell_form.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_controller.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_scene_controller.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop_policy.dart';
import 'package:omninest/features/backdrop/presentation/app_backdrop_surface.dart';
import 'package:omninest/app/theme/backdrop_scrim_colors.dart';

/// 在路由内容下方承载唯一应用背景实例。
class AppBackdropHost extends ConsumerWidget {
  const AppBackdropHost({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backdropState =
        ref.watch(appBackdropControllerProvider).asData?.value ??
        const AppBackdropState();
    final policy = ref.watch(appBackdropSceneControllerProvider).policy;
    final asset = backdropState.selectedBackdrop;
    final enabled = policy.visible && backdropState.hasActiveBackdrop;
    final motionAllowed =
        enabled &&
        policy.motionAllowed &&
        !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);
    final effectivePolicy = AppBackdropPolicy(
      scene: policy.scene,
      visible: policy.visible,
      playbackMode: policy.playbackMode,
      readabilityMode: policy.readabilityMode,
      motionAllowed: motionAllowed,
      environmentMode: policy.environmentMode,
    );
    // 环境模式仅在移动壳层下折算为壁纸强度；桌面端保持原有可读性语义，
    // 避免这次移动端空间重构改变桌面视觉基线。
    final mobileShell = shouldUseResponsiveMobileShell(
      mobilePlatform: isMobilePlatform,
      width: MediaQuery.sizeOf(context).width,
    );
    final presentation =
        mobileShell
            ? AppEnvironmentPresentation.of(policy.environmentMode)
            : null;
    // 条件子项必须携带稳定 Key：无 Key 时 Stack 按位置匹配，可见性翻转会
    // 让路由内容被错误复用到兄弟元素之下并整树重挂（Router 期间 setState 断言）。
    return Stack(
      fit: StackFit.expand,
      children: [
        if (policy.visible)
          const Positioned.fill(
            key: ValueKey<String>('omninest.backdrop.default'),
            child: _DefaultAppBackdrop(),
          ),
        Positioned.fill(
          key: const ValueKey<String>('omninest.backdrop.surface'),
          child: AnimatedOpacity(
            opacity: enabled ? (presentation?.wallpaperOpacity ?? 1) : 0,
            duration:
                MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            child: AppBackdropSurface(
              asset: asset,
              settings: backdropState.settings,
              policy: effectivePolicy,
              environmentBlurSigma: presentation?.blurSigma ?? 0.0,
              active:
                  enabled &&
                  policy.playbackMode == AppBackdropPlaybackMode.continuous,
            ),
          ),
        ),
        // 移动壳层以环境模式遮罩替代桌面可读性渐变，避免两层遮罩叠加。
        if (enabled && presentation != null)
          _EnvironmentModeScrim(
            key: const ValueKey<String>('omninest.backdrop.environment-scrim'),
            mode: policy.environmentMode,
          ),
        if (enabled &&
            presentation == null &&
            policy.readabilityMode != AppBackdropReadabilityMode.none)
          _AppBackdropReadabilityLayer(
            key: const ValueKey<String>('omninest.backdrop.readability'),
            mode: policy.readabilityMode,
          ),
        Positioned.fill(
          key: const ValueKey<String>('omninest.backdrop.content'),
          child: RepaintBoundary(child: child),
        ),
      ],
    );
  }
}

class _DefaultAppBackdrop extends StatelessWidget {
  const _DefaultAppBackdrop();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 无壁纸（Web / 未启用）时的舞台底：深色提亮一档，避免玻璃模块
    // 内容卡与纯黑底叠出整体过暗的观感；浅色维持表面色。
    final stage =
        scheme.brightness == Brightness.dark
            ? scheme.surfaceContainerLow
            : scheme.surface;
    return ColoredBox(color: stage);
  }
}

/// 环境模式遮罩：ambient 渐变、focus/utility 近实底。
///
/// 深色主题用黑色压暗，浅色主题用主题表面色提亮，保证两种外观下
/// 前景内容都落在可读表面上。
class _EnvironmentModeScrim extends StatelessWidget {
  const _EnvironmentModeScrim({required this.mode, super.key});

  final AppEnvironmentMode mode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final base = dark ? Colors.black : scheme.surface;
    Widget scrim;
    switch (mode) {
      case AppEnvironmentMode.immersive:
        scrim = const SizedBox.shrink();
      case AppEnvironmentMode.ambient:
        // 样例两段式：顶部轻压（.28），32% 处即入深底——内容区快速可读。
        scrim = DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                base.withValues(alpha: dark ? 0.28 : 0.44),
                base.withValues(alpha: dark ? 0.89 : 0.94),
              ],
              stops: const <double>[0, 0.32],
            ),
          ),
        );
      case AppEnvironmentMode.focus:
        scrim = ColoredBox(color: base.withValues(alpha: dark ? 0.78 : 0.90));
      case AppEnvironmentMode.utility:
        scrim = ColoredBox(color: base.withValues(alpha: dark ? 0.91 : 0.95));
    }
    return IgnorePointer(child: scrim);
  }
}

class _AppBackdropReadabilityLayer extends StatelessWidget {
  const _AppBackdropReadabilityLayer({required this.mode, super.key});

  final AppBackdropReadabilityMode mode;

  @override
  Widget build(BuildContext context) {
    final colors = switch (mode) {
      AppBackdropReadabilityMode.none => const <Color>[
        Colors.transparent,
        Colors.transparent,
        Colors.transparent,
      ],
      AppBackdropReadabilityMode.minimal => const <Color>[
        BackdropScrimColors.minimalTop,
        BackdropScrimColors.minimalMid,
        BackdropScrimColors.minimalBottom,
      ],
      AppBackdropReadabilityMode.content => const <Color>[
        BackdropScrimColors.contentTop,
        BackdropScrimColors.contentMid,
        BackdropScrimColors.contentBottom,
      ],
      AppBackdropReadabilityMode.work => const <Color>[
        BackdropScrimColors.workTop,
        BackdropScrimColors.workMid,
        BackdropScrimColors.workBottom,
      ],
      AppBackdropReadabilityMode.immersive => const <Color>[
        BackdropScrimColors.immersiveTop,
        BackdropScrimColors.immersiveMid,
        BackdropScrimColors.immersiveBottom,
      ],
    };
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: colors,
            stops: const <double>[0, 0.48, 1],
          ),
        ),
      ),
    );
  }
}
