import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_controller.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_scene_controller.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop_policy.dart';
import 'package:omninest/features/backdrop/presentation/app_backdrop_surface.dart';

String? _lastHostSnapshot;

/// 在路由内容下方承载唯一应用背景实例。
class AppBackdropHost extends ConsumerWidget {
  const AppBackdropHost({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncState = ref.watch(appBackdropControllerProvider);
    final backdropState = asyncState.asData?.value ?? const AppBackdropState();
    final policy = ref.watch(appBackdropSceneControllerProvider).policy;
    final asset = backdropState.selectedBackdrop;
    final enabled = policy.visible && backdropState.hasActiveBackdrop;
    final snapshot =
        'loading=${asyncState.isLoading} err=${asyncState.hasError} '
        'policy=${policy.scene.name}/${policy.visible}/${policy.motionAllowed} '
        'enabled=${backdropState.settings.enabled} '
        'selected=${backdropState.settings.selectedBackdropId} '
        'asset=${asset?.id} missing=${asset?.missing} '
        'active=${backdropState.hasActiveBackdrop} render=$enabled';
    if (snapshot != _lastHostSnapshot) {
      _lastHostSnapshot = snapshot;
      if (kDebugMode) {
        debugPrint('[Backdrop] host $snapshot');
      }
    }
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
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        if (policy.visible) const Positioned.fill(child: _DefaultAppBackdrop()),
        Positioned.fill(
          child: AnimatedOpacity(
            opacity: enabled ? 1 : 0,
            duration:
                MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: AppBackdropSurface(
              asset: asset,
              settings: backdropState.settings,
              policy: effectivePolicy,
              active:
                  enabled &&
                  policy.playbackMode == AppBackdropPlaybackMode.continuous,
            ),
          ),
        ),
        if (enabled &&
            policy.readabilityMode != AppBackdropReadabilityMode.none)
          _AppBackdropReadabilityLayer(mode: policy.readabilityMode),
        Positioned.fill(child: child),
      ],
    );
  }
}

class _DefaultAppBackdrop extends StatelessWidget {
  const _DefaultAppBackdrop();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: Theme.of(context).colorScheme.surface);
  }
}

class _AppBackdropReadabilityLayer extends StatelessWidget {
  const _AppBackdropReadabilityLayer({required this.mode});

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
        Color(0x12000000),
        Color(0x05000000),
        Color(0x18000000),
      ],
      AppBackdropReadabilityMode.content => const <Color>[
        Color(0x40000000),
        Color(0x12000000),
        Color(0x4D000000),
      ],
      AppBackdropReadabilityMode.work => const <Color>[
        Color(0xEB000000),
        Color(0xE0000000),
        Color(0xF0000000),
      ],
      AppBackdropReadabilityMode.immersive => const <Color>[
        Color(0x26000000),
        Color(0x08000000),
        Color(0x33000000),
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
