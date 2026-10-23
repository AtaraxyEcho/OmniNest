import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/mobile_shell/mobile_environment_scope.dart';
import 'package:omninest/app/mobile_shell/mobile_shell_form.dart';
import 'package:omninest/app/theme/backdrop_scrim_colors.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_controller.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_scene_controller.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop_policy.dart';
import 'package:omninest/features/backdrop/presentation/app_backdrop_surface.dart';

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
    // 环境层的底、壁纸强度与遮罩必须和内容极性同源：都取壳层解析出的那一档。
    final envPalette =
        mobileShell ? mobileEnvPaletteFor(Theme.of(context)) : null;
    final lightPolarity = envPalette?.brightness == Brightness.light;
    final presentation =
        mobileShell
            ? AppEnvironmentPresentation.of(policy.environmentMode)
            : null;
    // 条件子项必须携带稳定 Key：无 Key 时 Stack 按位置匹配，可见性翻转会
    // 让路由内容被错误复用到兄弟元素之下并整树重挂（Router 期间 setState 断言）。
    Widget surface = AppBackdropSurface(
      asset: asset,
      settings: backdropState.settings,
      policy: effectivePolicy,
      environmentBlurSigma: presentation?.blurSigma ?? 0.0,
      active:
          enabled && policy.playbackMode == AppBackdropPlaybackMode.continuous,
    );
    // 浅态摄影档对照片本身做 saturate/contrast/brightness（样例
    // `[data-mode="immersive"] .environment > img`），画布档照片直接不显示。
    if (presentation != null &&
        lightPolarity &&
        presentation.hasLightPhotoFilter) {
      surface = ColorFiltered(
        colorFilter: ColorFilter.matrix(_lightPhotoMatrix(presentation)),
        child: surface,
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        if (policy.visible)
          Positioned.fill(
            key: const ValueKey<String>('omninest.backdrop.default'),
            child: _DefaultAppBackdrop(palette: envPalette),
          ),
        Positioned.fill(
          key: const ValueKey<String>('omninest.backdrop.surface'),
          child: AnimatedOpacity(
            opacity:
                enabled
                    ? (presentation?.opacityFor(light: lightPolarity) ?? 1)
                    : 0,
            duration:
                MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            child: surface,
          ),
        ),
        // 移动壳层以环境模式遮罩替代桌面可读性渐变，避免两层遮罩叠加。
        if (enabled && presentation != null)
          _EnvironmentModeScrim(
            key: const ValueKey<String>('omninest.backdrop.environment-scrim'),
            mode: policy.environmentMode,
            palette: envPalette,
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
  const _DefaultAppBackdrop({this.palette});

  /// 壳层解析出的环境极性；null 表示桌面端，舞台底沿用主题容器色。
  final MobileEnvPalette? palette;

  @override
  Widget build(BuildContext context) {
    final env = palette;
    // 舞台底必须跟内容极性同源：根主题是浅色而环境极性判成暗（壁纸采样为暗）时，
    // 取主题的容器色会把白字内容压在白底上。暗态的实底比 stage 提亮一档，
    // 避免玻璃卡片叠纯黑整体过暗。
    if (env != null) {
      return ColoredBox(color: env.stageSolid);
    }
    final scheme = Theme.of(context).colorScheme;
    final stage =
        scheme.brightness == Brightness.dark
            ? scheme.surfaceContainerLow
            : scheme.surface;
    return ColoredBox(color: stage);
  }
}

/// 环境模式遮罩：暗态按档位压暗，浅态按档位换面。
///
/// 两极性不是同一配方的深浅两档：样例第 4 层规定浅态只有沉浸档仍是摄影面
/// （墨色压暗渐变，照片满显），ambient/focus/utility 照片 `opacity: 0`、
/// 环境层平涂 `#e9eee7` 当真实画布。桌面端不注册极性，走暗态分支。
class _EnvironmentModeScrim extends StatelessWidget {
  const _EnvironmentModeScrim({required this.mode, this.palette, super.key});

  final AppEnvironmentMode mode;

  /// 壳层解析出的环境极性；浅态走画布/摄影分档，暗态与桌面端走压暗分支。
  final MobileEnvPalette? palette;

  @override
  Widget build(BuildContext context) {
    final env = palette;
    if (env != null && env.brightness == Brightness.light) {
      return IgnorePointer(child: _LightEnvironmentWash(mode: mode));
    }
    // 余下分支只服务暗态：黑色压暗，不做亮度双分叉。
    Widget scrim;
    switch (mode) {
      case AppEnvironmentMode.immersive:
        scrim = const SizedBox.shrink();
      case AppEnvironmentMode.ambient:
        // 两段式：顶部轻压 28%，32% 处即入深底，内容区快速可读。
        scrim = DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Colors.black.withValues(alpha: 0.28),
                Colors.black.withValues(alpha: 0.89),
              ],
              stops: const <double>[0, 0.32],
            ),
          ),
        );
      case AppEnvironmentMode.focus:
        scrim = ColoredBox(color: Colors.black.withValues(alpha: 0.78));
      case AppEnvironmentMode.utility:
        scrim = ColoredBox(color: Colors.black.withValues(alpha: 0.91));
    }
    return IgnorePointer(child: scrim);
  }
}

/// 浅态纸色洗色：按环境模式取样例 `.environment-color` 的最终生效配方。
class _LightEnvironmentWash extends StatelessWidget {
  const _LightEnvironmentWash({required this.mode});

  final AppEnvironmentMode mode;

  @override
  Widget build(BuildContext context) {
    return switch (mode) {
      AppEnvironmentMode.immersive => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              BackdropStageColors.lightImmersiveStart,
              BackdropStageColors.lightImmersiveMid,
              BackdropStageColors.lightImmersiveEnd,
            ],
            stops: <double>[0, 0.42, 1],
          ),
        ),
      ),
      AppEnvironmentMode.ambient => const ColoredBox(
        color: BackdropStageColors.lightPaperWash,
      ),
      AppEnvironmentMode.focus => const ColoredBox(
        color: BackdropStageColors.lightPaperWash,
      ),
      AppEnvironmentMode.utility => const ColoredBox(
        color: BackdropStageColors.lightPaperWash,
      ),
    };
  }
}

/// 把 CSS `saturate(s) contrast(c) brightness(b)` 合成一个 5x4 颜色矩阵。
///
/// 三步都是逐通道仿射，合成后线性部分是 diag(b*c)·S(saturate)，
/// 偏移是 b*0.5*(1-c)：对比度绕 0.5 旋转，亮度直接乘。
List<double> _lightPhotoMatrix(AppEnvironmentPresentation presentation) {
  final s = presentation.lightPhotoSaturate ?? 1;
  final c = presentation.lightPhotoContrast ?? 1;
  final b = presentation.lightPhotoBrightness ?? 1;
  final gain = b * c;
  final offset = b * 0.5 * (1 - c);
  return <double>[
    gain * (0.213 + 0.787 * s),
    gain * (0.715 - 0.715 * s),
    gain * (0.072 - 0.072 * s),
    0,
    offset,
    gain * (0.213 - 0.213 * s),
    gain * (0.715 + 0.285 * s),
    gain * (0.072 - 0.072 * s),
    0,
    offset,
    gain * (0.213 - 0.213 * s),
    gain * (0.715 - 0.715 * s),
    gain * (0.072 + 0.928 * s),
    0,
    offset,
    0,
    0,
    0,
    1,
    0,
  ];
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
