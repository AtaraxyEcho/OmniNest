import 'package:flutter/material.dart';
import 'package:omninest/app/theme/feature/admin_colors.dart';
import 'package:omninest/core/theme/workstation_skin.dart';

/// Admin 模块“建筑极简主义工位”皮肤。
///
/// 遵循 architectural-minimalism-ui 规范：Zinc 中性冷灰阶、0px 纯直角、
/// 1px 细线边框、零阴影零渐变、语义状态色仅用于状态点/状态线/小徽章。
/// 公共色板与组件主题由 core/theme/workstation_skin.dart 提供，
/// 此处将 WorkstationPalette 映射为 AdminColors 扩展的 Zinc 取值。
abstract final class AdminWorkstationPalette {
  static const AdminColors darkColors = AdminColors(
    surface: WorkstationPalette.canvasDark,
    surfaceContainerLowest: WorkstationPalette.canvasDark,
    surfaceContainerLow: WorkstationPalette.surfaceLowDark,
    surfaceContainer: WorkstationPalette.containerDark,
    surfaceContainerHigh: WorkstationPalette.containerHighDark,
    surfaceContainerHighest: WorkstationPalette.hoverDark,
    onSurface: WorkstationPalette.textPrimaryDark,
    onSurfaceVariant: WorkstationPalette.textSecondaryDark,
    primary: WorkstationPalette.textPrimaryDark,
    primaryContainer: WorkstationPalette.hoverDark,
    secondary: WorkstationPalette.textSecondaryDark,
    tertiary: WorkstationPalette.cyan,
    error: WorkstationPalette.rose,
    outlineVariant: WorkstationPalette.lineDark,
    success: WorkstationPalette.emerald,
    warning: WorkstationPalette.amber,
    info: WorkstationPalette.cyan,
  );

  static const AdminColors lightColors = AdminColors(
    surface: WorkstationPalette.canvasLight,
    surfaceContainerLowest: WorkstationPalette.containerLight,
    surfaceContainerLow: WorkstationPalette.surfaceLowLight,
    surfaceContainer: WorkstationPalette.containerLight,
    surfaceContainerHigh: WorkstationPalette.containerHighLight,
    surfaceContainerHighest: WorkstationPalette.hoverLight,
    onSurface: WorkstationPalette.textPrimaryLight,
    onSurfaceVariant: WorkstationPalette.textSecondaryLight,
    primary: WorkstationPalette.textPrimaryLight,
    primaryContainer: WorkstationPalette.hoverLight,
    secondary: WorkstationPalette.textSecondaryLight,
    tertiary: WorkstationPalette.cyanDeep,
    error: WorkstationPalette.roseDeep,
    outlineVariant: WorkstationPalette.lineLight,
    success: WorkstationPalette.emeraldDeep,
    warning: WorkstationPalette.amberDeep,
    info: WorkstationPalette.cyanDeep,
  );

  static AdminColors colorsOf(Brightness brightness) {
    return brightness == Brightness.dark ? darkColors : lightColors;
  }
}

/// 将全局主题转换为 Admin 工位主题并在子树生效。
///
/// 用法：包裹 AdminShell 根部。ColorScheme、组件形状（全直角）、
/// AdminColors 扩展在此处统一替换；对话框等经由 context 打开的浮层
/// 会继承捕获的主题。
class AdminWorkstationScope extends StatelessWidget {
  const AdminWorkstationScope({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final brightness = base.brightness;
    final scheme = WorkstationPalette.schemeOf(brightness);
    final admin = AdminWorkstationPalette.colorsOf(brightness);
    final data = workstationThemeData(
      base: base,
      scheme: scheme,
      overlayExtensions: <ThemeExtension<dynamic>>[admin],
      progressAccent: WorkstationPalette.emerald,
    );
    return Theme(data: data, child: child);
  }
}
