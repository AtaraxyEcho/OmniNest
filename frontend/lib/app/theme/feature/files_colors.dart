import 'package:flutter/material.dart';
import 'package:omninest/app/theme/global_theme_colors.dart';

/// Files 模块主题扩展
///
/// 从 GlobalThemeColors 派生，保留文件管理专属 token。
@immutable
class FilesColors extends ThemeExtension<FilesColors> {
  const FilesColors({
    required this.surface,
    required this.surfaceContainerLow,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.outlineVariant,
    required this.primary,
    required this.primaryContainer,
    required this.tertiary,
    required this.error,
    required this.brandTeal,
    required this.sidebarSelectedBg,
    required this.sidebarSelectedBorder,
    required this.sidebarSelectedFg,
    required this.sidebarOnSurfaceVariant,
    required this.sidebarHoverBg,
    required this.storageAccent,
    required this.folderIcon,
    required this.documentIcon,
    required this.imageIcon,
    required this.videoIcon,
    required this.audioIcon,
    required this.archiveIcon,
    required this.success,
    required this.warning,
    required this.selectedBg,
    required this.selectedBorder,
  });

  final Color surface;
  final Color surfaceContainerLow;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color surfaceContainerHighest;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color outlineVariant;
  final Color primary;
  final Color primaryContainer;
  final Color tertiary;
  final Color error;
  final Color brandTeal;
  final Color sidebarSelectedBg;
  final Color sidebarSelectedBorder;
  final Color sidebarSelectedFg;
  final Color sidebarOnSurfaceVariant;
  final Color sidebarHoverBg;
  final Color storageAccent;
  final Color folderIcon;
  final Color documentIcon;
  final Color imageIcon;
  final Color videoIcon;
  final Color audioIcon;
  final Color archiveIcon;
  final Color success;
  final Color warning;
  final Color selectedBg;
  final Color selectedBorder;

  /// 从全局主题色派生 Files 模块专属色
  factory FilesColors.fromGlobal(GlobalThemeColors base) {
    return FilesColors(
      surface: base.surface,
      surfaceContainerLow: base.surfaceContainerLow,
      surfaceContainer: base.surfaceContainer,
      surfaceContainerHigh: base.surfaceContainerHigh,
      surfaceContainerHighest: base.surfaceContainerHighest,
      onSurface: base.onSurface,
      onSurfaceVariant: base.onSurfaceVariant,
      outlineVariant: base.outlineVariant,
      primary: base.primary,
      primaryContainer: base.primaryContainer,
      tertiary: base.accentCool,
      error: base.error,
      brandTeal: base.accentCool,
      sidebarSelectedBg: base.selectedOverlay,
      sidebarSelectedBorder:
          Color.lerp(Colors.transparent, base.primary, 0.25)!,
      sidebarSelectedFg: base.onSurface,
      sidebarOnSurfaceVariant: base.onSurfaceVariant,
      sidebarHoverBg: base.hoverOverlay,
      storageAccent: base.primary,
      folderIcon: base.accentCool,
      documentIcon: base.onSurfaceVariant,
      imageIcon: base.accentWarm,
      videoIcon: base.tertiary,
      audioIcon: base.onSurface,
      archiveIcon: base.onSurfaceVariant,
      success: base.success,
      warning: base.warning,
      selectedBg: base.selectedOverlay,
      selectedBorder: Color.lerp(Colors.transparent, base.primary, 0.3)!,
    );
  }

  static const List<FilesColors> values = [];

  @override
  FilesColors copyWith({
    Color? surface,
    Color? surfaceContainerLow,
    Color? surfaceContainer,
    Color? surfaceContainerHigh,
    Color? surfaceContainerHighest,
    Color? onSurface,
    Color? onSurfaceVariant,
    Color? outlineVariant,
    Color? primary,
    Color? primaryContainer,
    Color? tertiary,
    Color? error,
    Color? brandTeal,
    Color? sidebarSelectedBg,
    Color? sidebarSelectedBorder,
    Color? sidebarSelectedFg,
    Color? sidebarOnSurfaceVariant,
    Color? sidebarHoverBg,
    Color? storageAccent,
    Color? folderIcon,
    Color? documentIcon,
    Color? imageIcon,
    Color? videoIcon,
    Color? audioIcon,
    Color? archiveIcon,
    Color? success,
    Color? warning,
    Color? selectedBg,
    Color? selectedBorder,
  }) {
    return FilesColors(
      surface: surface ?? this.surface,
      surfaceContainerLow: surfaceContainerLow ?? this.surfaceContainerLow,
      surfaceContainer: surfaceContainer ?? this.surfaceContainer,
      surfaceContainerHigh: surfaceContainerHigh ?? this.surfaceContainerHigh,
      surfaceContainerHighest:
          surfaceContainerHighest ?? this.surfaceContainerHighest,
      onSurface: onSurface ?? this.onSurface,
      onSurfaceVariant: onSurfaceVariant ?? this.onSurfaceVariant,
      outlineVariant: outlineVariant ?? this.outlineVariant,
      primary: primary ?? this.primary,
      primaryContainer: primaryContainer ?? this.primaryContainer,
      tertiary: tertiary ?? this.tertiary,
      error: error ?? this.error,
      brandTeal: brandTeal ?? this.brandTeal,
      sidebarSelectedBg: sidebarSelectedBg ?? this.sidebarSelectedBg,
      sidebarSelectedBorder:
          sidebarSelectedBorder ?? this.sidebarSelectedBorder,
      sidebarSelectedFg: sidebarSelectedFg ?? this.sidebarSelectedFg,
      sidebarOnSurfaceVariant:
          sidebarOnSurfaceVariant ?? this.sidebarOnSurfaceVariant,
      sidebarHoverBg: sidebarHoverBg ?? this.sidebarHoverBg,
      storageAccent: storageAccent ?? this.storageAccent,
      folderIcon: folderIcon ?? this.folderIcon,
      documentIcon: documentIcon ?? this.documentIcon,
      imageIcon: imageIcon ?? this.imageIcon,
      videoIcon: videoIcon ?? this.videoIcon,
      audioIcon: audioIcon ?? this.audioIcon,
      archiveIcon: archiveIcon ?? this.archiveIcon,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      selectedBg: selectedBg ?? this.selectedBg,
      selectedBorder: selectedBorder ?? this.selectedBorder,
    );
  }

  @override
  FilesColors lerp(FilesColors? other, double t) {
    if (other is! FilesColors) return this;
    return FilesColors(
      surface: Color.lerp(surface, other.surface, t)!,
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
      outlineVariant: Color.lerp(outlineVariant, other.outlineVariant, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryContainer:
          Color.lerp(primaryContainer, other.primaryContainer, t)!,
      tertiary: Color.lerp(tertiary, other.tertiary, t)!,
      error: Color.lerp(error, other.error, t)!,
      brandTeal: Color.lerp(brandTeal, other.brandTeal, t)!,
      sidebarSelectedBg:
          Color.lerp(sidebarSelectedBg, other.sidebarSelectedBg, t)!,
      sidebarSelectedBorder:
          Color.lerp(sidebarSelectedBorder, other.sidebarSelectedBorder, t)!,
      sidebarSelectedFg:
          Color.lerp(sidebarSelectedFg, other.sidebarSelectedFg, t)!,
      sidebarOnSurfaceVariant:
          Color.lerp(
            sidebarOnSurfaceVariant,
            other.sidebarOnSurfaceVariant,
            t,
          )!,
      sidebarHoverBg: Color.lerp(sidebarHoverBg, other.sidebarHoverBg, t)!,
      storageAccent: Color.lerp(storageAccent, other.storageAccent, t)!,
      folderIcon: Color.lerp(folderIcon, other.folderIcon, t)!,
      documentIcon: Color.lerp(documentIcon, other.documentIcon, t)!,
      imageIcon: Color.lerp(imageIcon, other.imageIcon, t)!,
      videoIcon: Color.lerp(videoIcon, other.videoIcon, t)!,
      audioIcon: Color.lerp(audioIcon, other.audioIcon, t)!,
      archiveIcon: Color.lerp(archiveIcon, other.archiveIcon, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      selectedBg: Color.lerp(selectedBg, other.selectedBg, t)!,
      selectedBorder: Color.lerp(selectedBorder, other.selectedBorder, t)!,
    );
  }

  static FilesColors of(BuildContext context) {
    return Theme.of(context).extension<FilesColors>()!;
  }
}

extension FilesColorsExtension on BuildContext {
  FilesColors get filesColors => FilesColors.of(this);
}
