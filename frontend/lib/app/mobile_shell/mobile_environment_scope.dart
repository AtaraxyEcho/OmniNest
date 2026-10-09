import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/mobile_shell/mobile_shell_feature_bindings.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_polarity.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop_tone.dart';

/// 环境极性的唯一判定。
///
/// 壁纸在场时取采样亮度：亮壁纸配浅表，暗壁纸配暗表，中间调由
/// `AppBackdropTone` 判为暗。无壁纸的实底面随根主题明暗，避免
/// 「壳强制暗、页内随主题」的分裂态。
MobileEnvPalette resolveMobileEnvPalette({
  required bool backdropActive,
  required AppBackdropPolarity sampled,
  required Brightness brightness,
}) {
  if (!backdropActive) {
    return MobileEnvPalette.resolve(brightness);
  }
  return sampled == AppBackdropPolarity.light
      ? MobileEnvPalette.light
      : MobileEnvPalette.dark;
}

/// 当前主题实际生效的极性，供壳层与系统栏样式共用。
MobileEnvPalette watchMobileEnvPalette(WidgetRef ref, ThemeData baseTheme) {
  return resolveMobileEnvPalette(
    backdropActive: ref.watch(mobileShellLocalBackdropActiveProvider),
    sampled: ref.watch(appBackdropPolarityProvider),
    brightness: baseTheme.brightness,
  );
}

/// 给环境面子树注册当前壁纸极性对应的配色表。
///
/// 极性只在这里决定；空间根节点各包一次，避免每面重复 copyWith。
/// `ThemeData.copyWith(extensions:)` 是整体替换，因此必须带上既有扩展，
/// 否则模块调色板会丢。
class MobileEnvironmentScope extends ConsumerWidget {
  const MobileEnvironmentScope({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final base = Theme.of(context);
    return Theme(
      data: base.withEnvPalette(watchMobileEnvPalette(ref, base)),
      child: child,
    );
  }
}
