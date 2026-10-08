import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_polarity.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop_tone.dart';

/// 给环境面子树注册当前壁纸极性对应的配色表。
///
/// 极性只在这里决定，取值来自壁纸采样而不是明暗设置；空间根节点各包一次，
/// 避免每面重复 copyWith。`ThemeData.copyWith(extensions:)` 是整体替换，
/// 因此必须带上既有扩展，否则模块调色板会丢。
class MobileEnvironmentScope extends ConsumerWidget {
  const MobileEnvironmentScope({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final base = Theme.of(context);
    final palette =
        ref.watch(appBackdropPolarityProvider) == AppBackdropPolarity.light
            ? MobileEnvPalette.light
            : MobileEnvPalette.dark;
    return Theme(
      data: base.copyWith(extensions: [...base.extensions.values, palette]),
      child: child,
    );
  }
}
