import 'package:flutter/material.dart';
import 'package:omninest/app/theme/feature/files_colors.dart';
import 'package:omninest/core/theme/workstation_skin.dart';

/// Files 模块“建筑极简主义工位”皮肤调色映射。
///
/// 公共色板与组件主题由 core/theme/workstation_skin.dart 提供，
/// 此处保留色值转发常量与 FilesColors 扩展的 Zinc 取值映射，
/// 既有调用点无需改动。
abstract final class FilesWorkstationPalette {
  static const Color canvasDark = WorkstationPalette.canvasDark;
  static const Color surfaceLowDark = WorkstationPalette.surfaceLowDark;
  static const Color containerDark = WorkstationPalette.containerDark;
  static const Color containerHighDark = WorkstationPalette.containerHighDark;
  static const Color hoverDark = WorkstationPalette.hoverDark;
  static const Color lineDark = WorkstationPalette.lineDark;
  static const Color lineStrongDark = WorkstationPalette.lineStrongDark;
  static const Color textPrimaryDark = WorkstationPalette.textPrimaryDark;
  static const Color textSecondaryDark = WorkstationPalette.textSecondaryDark;
  static const Color outlineDark = WorkstationPalette.outlineDark;

  static const Color canvasLight = WorkstationPalette.canvasLight;
  static const Color surfaceLowLight = WorkstationPalette.surfaceLowLight;
  static const Color containerLight = WorkstationPalette.containerLight;
  static const Color containerHighLight = WorkstationPalette.containerHighLight;
  static const Color hoverLight = WorkstationPalette.hoverLight;
  static const Color lineLight = WorkstationPalette.lineLight;
  static const Color lineStrongLight = WorkstationPalette.lineStrongLight;
  static const Color textPrimaryLight = WorkstationPalette.textPrimaryLight;
  static const Color textSecondaryLight = WorkstationPalette.textSecondaryLight;
  static const Color outlineLight = WorkstationPalette.outlineLight;

  static const Color emerald = WorkstationPalette.emerald;
  static const Color emeraldDeep = WorkstationPalette.emeraldDeep;
  static const Color emeraldBgDark = WorkstationPalette.emeraldBgDark;
  static const Color amber = WorkstationPalette.amber;
  static const Color amberDeep = WorkstationPalette.amberDeep;
  static const Color amberBgDark = WorkstationPalette.amberBgDark;
  static const Color rose = WorkstationPalette.rose;
  static const Color roseDeep = WorkstationPalette.roseDeep;
  static const Color roseBorderDark = WorkstationPalette.roseBorderDark;
  static const Color roseBgDark = WorkstationPalette.roseBgDark;
  static const Color cyan = WorkstationPalette.cyan;
  static const Color cyanDeep = WorkstationPalette.cyanDeep;
  static const Color cyanBgDark = WorkstationPalette.cyanBgDark;

  static const FilesColors darkColors = FilesColors(
    surface: WorkstationPalette.canvasDark,
    surfaceContainerLow: WorkstationPalette.surfaceLowDark,
    surfaceContainer: WorkstationPalette.containerDark,
    surfaceContainerHigh: WorkstationPalette.containerHighDark,
    surfaceContainerHighest: WorkstationPalette.hoverDark,
    onSurface: WorkstationPalette.textPrimaryDark,
    onSurfaceVariant: WorkstationPalette.textSecondaryDark,
    outlineVariant: WorkstationPalette.lineDark,
    primary: WorkstationPalette.textPrimaryDark,
    primaryContainer: WorkstationPalette.hoverDark,
    tertiary: WorkstationPalette.cyan,
    error: WorkstationPalette.rose,
    brandTeal: WorkstationPalette.textSecondaryDark,
    sidebarSelectedBg: WorkstationPalette.hoverDark,
    sidebarSelectedBorder: WorkstationPalette.lineDark,
    sidebarSelectedFg: WorkstationPalette.textPrimaryDark,
    sidebarOnSurfaceVariant: WorkstationPalette.textSecondaryDark,
    sidebarHoverBg: WorkstationPalette.containerDark,
    storageAccent: WorkstationPalette.emerald,
    folderIcon: WorkstationPalette.textSecondaryDark,
    documentIcon: WorkstationPalette.textSecondaryDark,
    imageIcon: WorkstationPalette.textSecondaryDark,
    videoIcon: WorkstationPalette.textSecondaryDark,
    audioIcon: WorkstationPalette.textSecondaryDark,
    archiveIcon: WorkstationPalette.textSecondaryDark,
    success: WorkstationPalette.emerald,
    warning: WorkstationPalette.amber,
    selectedBg: WorkstationPalette.hoverDark,
    selectedBorder: WorkstationPalette.lineStrongDark,
  );

  static const FilesColors lightColors = FilesColors(
    surface: WorkstationPalette.canvasLight,
    surfaceContainerLow: WorkstationPalette.surfaceLowLight,
    surfaceContainer: WorkstationPalette.containerLight,
    surfaceContainerHigh: WorkstationPalette.containerHighLight,
    surfaceContainerHighest: WorkstationPalette.hoverLight,
    onSurface: WorkstationPalette.textPrimaryLight,
    onSurfaceVariant: WorkstationPalette.textSecondaryLight,
    outlineVariant: WorkstationPalette.lineLight,
    primary: WorkstationPalette.textPrimaryLight,
    primaryContainer: WorkstationPalette.hoverLight,
    tertiary: WorkstationPalette.cyanDeep,
    error: WorkstationPalette.roseDeep,
    brandTeal: WorkstationPalette.textSecondaryLight,
    sidebarSelectedBg: WorkstationPalette.containerLight,
    sidebarSelectedBorder: WorkstationPalette.lineLight,
    sidebarSelectedFg: WorkstationPalette.textPrimaryLight,
    sidebarOnSurfaceVariant: WorkstationPalette.textSecondaryLight,
    sidebarHoverBg: WorkstationPalette.surfaceLowLight,
    storageAccent: WorkstationPalette.emeraldDeep,
    folderIcon: WorkstationPalette.textSecondaryLight,
    documentIcon: WorkstationPalette.textSecondaryLight,
    imageIcon: WorkstationPalette.textSecondaryLight,
    videoIcon: WorkstationPalette.textSecondaryLight,
    audioIcon: WorkstationPalette.textSecondaryLight,
    archiveIcon: WorkstationPalette.textSecondaryLight,
    success: WorkstationPalette.emeraldDeep,
    warning: WorkstationPalette.amberDeep,
    selectedBg: WorkstationPalette.surfaceLowLight,
    selectedBorder: WorkstationPalette.textSecondaryLight,
  );

  static FilesColors colorsOf(Brightness brightness) {
    return brightness == Brightness.dark ? darkColors : lightColors;
  }

  static ColorScheme schemeOf(Brightness brightness) {
    return WorkstationPalette.schemeOf(brightness);
  }
}

/// 将全局主题转换为 Files 工位主题并在子树生效。
///
/// 用法：包裹模块 Shell 根部。ColorScheme、组件形状（全直角）、
/// FilesColors 扩展在此处统一替换；对话框等经由 context 打开的浮层
/// 会继承捕获的主题。
class FilesWorkstationScope extends StatelessWidget {
  const FilesWorkstationScope({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final brightness = base.brightness;
    final scheme = WorkstationPalette.schemeOf(brightness);
    final files = FilesWorkstationPalette.colorsOf(brightness);
    final data = workstationThemeData(
      base: base,
      scheme: scheme,
      overlayExtensions: <ThemeExtension<dynamic>>[files],
      progressAccent: files.storageAccent,
    );
    return Theme(data: data, child: child);
  }
}
