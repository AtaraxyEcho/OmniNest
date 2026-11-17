import 'package:flutter/material.dart';
import 'package:omninest/app/theme/global_theme_colors.dart';

/// Admin 模块主题扩展
///
/// 从 GlobalThemeColors 派生，保留管理端专属 token。
class AdminColors extends ThemeExtension<AdminColors> {
  const AdminColors({
    required this.surface,
    required this.surfaceContainerLowest,
    required this.surfaceContainerLow,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.primary,
    required this.primaryContainer,
    required this.secondary,
    required this.tertiary,
    required this.error,
    required this.outlineVariant,
    required this.success,
    required this.warning,
    required this.info,
  });

  final Color surface;
  final Color surfaceContainerLowest;
  final Color surfaceContainerLow;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color surfaceContainerHighest;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color primary;
  final Color primaryContainer;
  final Color secondary;
  final Color tertiary;
  final Color error;
  final Color outlineVariant;
  final Color success;
  final Color warning;
  final Color info;

  /// 从全局主题色派生 Admin 模块专属色
  factory AdminColors.fromGlobal(GlobalThemeColors base) {
    return AdminColors(
      surface: base.surface,
      surfaceContainerLowest: base.surfaceContainerLowest,
      surfaceContainerLow: base.surfaceContainerLow,
      surfaceContainer: base.surfaceContainer,
      surfaceContainerHigh: base.surfaceContainerHigh,
      surfaceContainerHighest: base.surfaceContainerHighest,
      onSurface: base.onSurface,
      onSurfaceVariant: base.onSurfaceVariant,
      primary: base.primary,
      primaryContainer: base.primaryContainer,
      secondary: base.secondary,
      tertiary: base.accentCool,
      error: base.error,
      outlineVariant: base.outlineVariant,
      success: base.success,
      warning: base.warning,
      info: base.info,
    );
  }

  @override
  AdminColors copyWith({
    Color? surface,
    Color? surfaceContainerLowest,
    Color? surfaceContainerLow,
    Color? surfaceContainer,
    Color? surfaceContainerHigh,
    Color? surfaceContainerHighest,
    Color? onSurface,
    Color? onSurfaceVariant,
    Color? primary,
    Color? primaryContainer,
    Color? secondary,
    Color? tertiary,
    Color? error,
    Color? outlineVariant,
    Color? success,
    Color? warning,
    Color? info,
  }) {
    return AdminColors(
      surface: surface ?? this.surface,
      surfaceContainerLowest:
          surfaceContainerLowest ?? this.surfaceContainerLowest,
      surfaceContainerLow: surfaceContainerLow ?? this.surfaceContainerLow,
      surfaceContainer: surfaceContainer ?? this.surfaceContainer,
      surfaceContainerHigh: surfaceContainerHigh ?? this.surfaceContainerHigh,
      surfaceContainerHighest:
          surfaceContainerHighest ?? this.surfaceContainerHighest,
      onSurface: onSurface ?? this.onSurface,
      onSurfaceVariant: onSurfaceVariant ?? this.onSurfaceVariant,
      primary: primary ?? this.primary,
      primaryContainer: primaryContainer ?? this.primaryContainer,
      secondary: secondary ?? this.secondary,
      tertiary: tertiary ?? this.tertiary,
      error: error ?? this.error,
      outlineVariant: outlineVariant ?? this.outlineVariant,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      info: info ?? this.info,
    );
  }

  @override
  AdminColors lerp(AdminColors? other, double t) {
    if (other is! AdminColors) return this;
    return AdminColors(
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceContainerLowest:
          Color.lerp(surfaceContainerLowest, other.surfaceContainerLowest, t)!,
      surfaceContainerLow:
          Color.lerp(surfaceContainerLow, other.surfaceContainerLow, t)!,
      surfaceContainer:
          Color.lerp(surfaceContainer, other.surfaceContainer, t)!,
      surfaceContainerHigh:
          Color.lerp(surfaceContainerHigh, other.surfaceContainerHigh, t)!,
      surfaceContainerHighest:
          Color.lerp(
            surfaceContainerHighest,
            other.surfaceContainerHighest,
            t,
          )!,
      onSurface: Color.lerp(onSurface, other.onSurface, t)!,
      onSurfaceVariant:
          Color.lerp(onSurfaceVariant, other.onSurfaceVariant, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryContainer:
          Color.lerp(primaryContainer, other.primaryContainer, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      tertiary: Color.lerp(tertiary, other.tertiary, t)!,
      error: Color.lerp(error, other.error, t)!,
      outlineVariant: Color.lerp(outlineVariant, other.outlineVariant, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      info: Color.lerp(info, other.info, t)!,
    );
  }

  static AdminColors of(BuildContext context) {
    return Theme.of(context).extension<AdminColors>()!;
  }
}

extension AdminColorsExtension on BuildContext {
  AdminColors get adminColors => AdminColors.of(this);
}
