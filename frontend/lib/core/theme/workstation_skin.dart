import 'package:flutter/material.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/control_tokens.dart';

/// 建筑极简主义工位皮肤公共核心。
///
/// 遵循 architectural-minimalism-ui 规范：Zinc 中性冷灰阶、0px 纯直角、
/// 1px 细线边框、零阴影零渐变、语义状态色仅用于状态点/状态线/小徽章。
/// Files 与 Admin 模块共用本核心，各自通过模块级 Scope 注入专属
/// ThemeExtension 后生效，不影响其他模块的全局主题。
abstract final class WorkstationPalette {
  static const Color canvasDark = Color(0xFF09090B);
  static const Color surfaceLowDark = Color(0xFF0F0F12);
  static const Color containerDark = Color(0xFF18181C);
  static const Color containerHighDark = Color(0xFF1E1E23);
  static const Color hoverDark = Color(0xFF222227);
  static const Color lineDark = Color(0xFF27272A);
  static const Color lineStrongDark = Color(0xFF52525B);
  static const Color textPrimaryDark = Color(0xFFF4F4F5);
  static const Color textSecondaryDark = Color(0xFFA1A1AA);
  static const Color outlineDark = Color(0xFF71717A);

  static const Color canvasLight = Color(0xFFF8F9FA);
  static const Color surfaceLowLight = Color(0xFFF4F4F5);
  static const Color containerLight = Color(0xFFFFFFFF);
  static const Color containerHighLight = Color(0xFFECECED);
  static const Color hoverLight = Color(0xFFE4E4E7);
  static const Color lineLight = Color(0xFFE4E4E7);
  static const Color lineStrongLight = Color(0xFF71717A);
  static const Color textPrimaryLight = Color(0xFF09090B);
  static const Color textSecondaryLight = Color(0xFF52525B);
  static const Color outlineLight = Color(0xFF71717A);

  static const Color emerald = Color(0xFF10B981);
  static const Color emeraldDeep = Color(0xFF047857);
  static const Color emeraldBgDark = Color(0xFF042F24);
  static const Color amber = Color(0xFFF59E0B);
  static const Color amberDeep = Color(0xFFB45309);
  static const Color amberBgDark = Color(0xFF2E1A05);
  static const Color rose = Color(0xFFEF4444);
  static const Color roseDeep = Color(0xFFDC2626);
  static const Color roseBorderDark = Color(0xFFB91C1C);
  static const Color roseBgDark = Color(0xFF2A0C0C);
  static const Color cyan = Color(0xFF06B6D4);
  static const Color cyanDeep = Color(0xFF0E7490);
  static const Color cyanBgDark = Color(0xFF062C3B);

  static ColorScheme schemeOf(Brightness brightness) {
    if (brightness == Brightness.dark) {
      return const ColorScheme(
        brightness: Brightness.dark,
        surface: canvasDark,
        onSurface: textPrimaryDark,
        onSurfaceVariant: textSecondaryDark,
        surfaceContainerLowest: canvasDark,
        surfaceContainerLow: surfaceLowDark,
        surfaceContainer: containerDark,
        surfaceContainerHigh: containerHighDark,
        surfaceContainerHighest: hoverDark,
        primary: textPrimaryDark,
        onPrimary: canvasDark,
        primaryContainer: hoverDark,
        onPrimaryContainer: textPrimaryDark,
        secondary: textSecondaryDark,
        onSecondary: canvasDark,
        secondaryContainer: lineDark,
        onSecondaryContainer: textPrimaryDark,
        tertiary: cyan,
        onTertiary: cyanBgDark,
        tertiaryContainer: cyanBgDark,
        onTertiaryContainer: textPrimaryDark,
        error: rose,
        onError: Colors.white,
        errorContainer: roseBgDark,
        onErrorContainer: textPrimaryDark,
        outline: lineStrongDark,
        outlineVariant: lineDark,
        shadow: Colors.black,
        scrim: Colors.black,
        inverseSurface: textPrimaryDark,
        onInverseSurface: canvasDark,
        inversePrimary: canvasDark,
        surfaceTint: Colors.transparent,
      );
    }
    return const ColorScheme(
      brightness: Brightness.light,
      surface: canvasLight,
      onSurface: textPrimaryLight,
      onSurfaceVariant: textSecondaryLight,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: surfaceLowLight,
      surfaceContainer: containerLight,
      surfaceContainerHigh: containerHighLight,
      surfaceContainerHighest: hoverLight,
      primary: textPrimaryLight,
      onPrimary: Colors.white,
      primaryContainer: hoverLight,
      onPrimaryContainer: textPrimaryLight,
      secondary: textSecondaryLight,
      onSecondary: Colors.white,
      secondaryContainer: lineLight,
      onSecondaryContainer: textPrimaryLight,
      tertiary: cyanDeep,
      onTertiary: Colors.white,
      tertiaryContainer: Color(0xFFD5F1F8),
      onTertiaryContainer: cyanBgDark,
      error: roseDeep,
      onError: Colors.white,
      errorContainer: Color(0xFFFBE9E9),
      onErrorContainer: roseBgDark,
      outline: lineStrongLight,
      outlineVariant: lineLight,
      shadow: Color(0x1F000000),
      scrim: Colors.black,
      inverseSurface: textPrimaryLight,
      onInverseSurface: canvasLight,
      inversePrimary: canvasLight,
      surfaceTint: Colors.transparent,
    );
  }
}

/// 工位皮肤标记扩展。
///
/// 由 [workstationThemeData] 统一注册，供 AppDropdown 等全局通用控件感知
/// 自身处于 Files / Admin 工位 Scope 内，从而切换为直角细线形态；
/// 非工位子树不携带本标记，全局默认外观不受影响。
class WorkstationSurfaceFlag extends ThemeExtension<WorkstationSurfaceFlag> {
  const WorkstationSurfaceFlag();

  @override
  WorkstationSurfaceFlag copyWith() => this;

  @override
  WorkstationSurfaceFlag lerp(
    covariant ThemeExtension<WorkstationSurfaceFlag>? other,
    double t,
  ) => this;
}

/// 在全局主题之上叠加工位皮肤：ColorScheme、全直角组件形状、
/// 细线边框与零阴影，并保留全局已注册的 ThemeExtension。
///
/// [overlayExtensions] 为模块专属扩展（如 FilesColors / AdminColors），
/// 会以类型为键覆盖基础主题中的同名扩展。
ThemeData workstationThemeData({
  required ThemeData base,
  required ColorScheme scheme,
  Iterable<ThemeExtension<dynamic>> overlayExtensions =
      const <ThemeExtension<dynamic>>[],
  Color progressAccent = WorkstationPalette.emerald,
}) {
  final isDark = scheme.brightness == Brightness.dark;
  final isDesktop = AppControlTokens.isDesktopDensity;
  final buttonHeight = isDesktop ? 32.0 : 44.0;
  final edgeShape = RoundedRectangleBorder(borderRadius: BorderRadius.zero);

  final extensions = Map<Object, ThemeExtension<dynamic>>.of(base.extensions);
  extensions[WorkstationSurfaceFlag] = const WorkstationSurfaceFlag();
  for (final extension in overlayExtensions) {
    extensions[extension.runtimeType] = extension;
  }

  final textTheme = base.textTheme.apply(
    bodyColor: scheme.onSurface,
    displayColor: scheme.onSurface,
  );

  return base.copyWith(
    colorScheme: scheme,
    extensions: extensions.values,
    textTheme: textTheme,
    splashFactory: NoSplash.splashFactory,
    visualDensity: VisualDensity.compact,
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: edgeShape.copyWith(
        side: BorderSide(color: scheme.outline, width: 1),
      ),
      titleTextStyle: textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      contentTextStyle: textTheme.bodyMedium,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: isDark ? WorkstationPalette.hoverDark : scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: edgeShape.copyWith(
        side: BorderSide(color: scheme.outline, width: 1),
      ),
      textStyle: textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
      labelTextStyle: WidgetStatePropertyAll(
        textTheme.labelSmall?.copyWith(
          fontFamily: AppTypography.monoFamily,
          fontFamilyFallback: AppTypography.monoFamilyFallback,
          letterSpacing: 1.2,
          color: scheme.onSurfaceVariant,
        ),
      ),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(
          isDark ? WorkstationPalette.hoverDark : scheme.surfaceContainer,
        ),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(0),
        shape: WidgetStatePropertyAll(
          edgeShape.copyWith(side: BorderSide(color: scheme.outline)),
        ),
        side: WidgetStatePropertyAll(BorderSide(color: scheme.outline)),
      ),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainer),
        elevation: const WidgetStatePropertyAll(0),
        shape: WidgetStatePropertyAll(
          edgeShape.copyWith(side: BorderSide(color: scheme.outline)),
        ),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: isDark ? scheme.onSurface : scheme.surfaceContainerHighest,
        border: Border.all(color: scheme.outline),
      ),
      textStyle: TextStyle(
        fontFamily: AppTypography.monoFamily,
        fontFamilyFallback: AppTypography.monoFamilyFallback,
        fontSize: AppTypography.labelSmall,
        letterSpacing: 0.4,
        color: isDark ? scheme.surface : scheme.onSurface,
      ),
      waitDuration: const Duration(milliseconds: 350),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(4),
      thumbColor: WidgetStatePropertyAll(scheme.outline),
      trackColor: WidgetStatePropertyAll(
        scheme.outlineVariant.withValues(alpha: 0.4),
      ),
      radius: Radius.zero,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: progressAccent,
      linearTrackColor: scheme.outlineVariant,
      circularTrackColor: scheme.outlineVariant,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor:
          isDark
              ? WorkstationPalette.surfaceLowDark
              : scheme.surfaceContainerLow,
      hintStyle: TextStyle(color: scheme.outline),
      // 默认 hairline（outlineVariant）细线；聚焦仅 1px 精准升为
      // onSurface，杜绝未聚焦输入框呈现“像选中态”的强边框。
      border: _outlineInputBorder(scheme.outlineVariant),
      enabledBorder: _outlineInputBorder(scheme.outlineVariant),
      focusedBorder: _outlineInputBorder(scheme.onSurface),
      errorBorder: _outlineInputBorder(scheme.error),
      focusedErrorBorder: _outlineInputBorder(scheme.error),
      isDense: true,
      // 内容内边距与 AppDropdown 闭合态对齐（其底部收 2px 补偿
      // EditableText 与 InputDecorator 的基线差）；最小高度同取
      // fieldHeight 令牌（与 AppDropdown 的 ConstrainedBox 完全一致），
      // 保证同一表单内 TextField 与 AppDropdown 渲染高度严格相等：
      // 无 helper 时 36/44，带 helper 时 46/54。
      contentPadding:
          isDesktop
              ? const EdgeInsets.fromLTRB(12, 8, 12, 6)
              : const EdgeInsets.fromLTRB(14, 12, 14, 10),
      constraints: BoxConstraints(minHeight: AppControlTokens.fieldHeight),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      side: BorderSide(color: scheme.outline, width: 1),
      visualDensity: VisualDensity.compact,
    ),
    radioTheme: RadioThemeData(
      visualDensity: VisualDensity.compact,
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return scheme.onSurface;
        }
        return scheme.outline;
      }),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        shape: WidgetStatePropertyAll(edgeShape),
        side: WidgetStatePropertyAll(BorderSide(color: scheme.outline)),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return isDark
                ? WorkstationPalette.hoverDark
                : scheme.surfaceContainerHighest;
          }
          return Colors.transparent;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? scheme.onSurface
              : scheme.onSurfaceVariant;
        }),
        textStyle: WidgetStatePropertyAll(
          textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: edgeShape,
        minimumSize: Size(0, buttonHeight),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        textStyle: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
        visualDensity: VisualDensity.compact,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: edgeShape,
        side: BorderSide(color: scheme.outline),
        minimumSize: Size(0, buttonHeight),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        textStyle: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
        visualDensity: VisualDensity.compact,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: edgeShape,
        minimumSize: Size(0, buttonHeight),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        visualDensity: VisualDensity.compact,
        foregroundColor: scheme.onSurfaceVariant,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        shape: edgeShape,
        visualDensity: VisualDensity.compact,
        foregroundColor: scheme.onSurfaceVariant,
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: edgeShape.copyWith(side: BorderSide(color: scheme.outlineVariant)),
      margin: EdgeInsets.zero,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      clipBehavior: Clip.none,
    ),
    listTileTheme: ListTileThemeData(
      shape: edgeShape,
      iconColor: scheme.onSurfaceVariant,
      textColor: scheme.onSurface,
      dense: true,
    ),
    chipTheme: ChipThemeData(
      shape: edgeShape.copyWith(side: BorderSide(color: scheme.outline)),
      backgroundColor: scheme.surfaceContainer,
      side: BorderSide(color: scheme.outlineVariant),
      labelStyle: textTheme.bodySmall?.copyWith(color: scheme.onSurface),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    ),
    dataTableTheme: DataTableThemeData(
      headingRowColor: WidgetStatePropertyAll(scheme.surfaceContainer),
      dataRowColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return isDark
              ? WorkstationPalette.hoverDark
              : scheme.surfaceContainerLow;
        }
        if (states.contains(WidgetState.hovered)) {
          return scheme.surfaceContainerHigh;
        }
        return scheme.surface;
      }),
      headingTextStyle: textTheme.labelSmall?.copyWith(
        fontFamily: AppTypography.monoFamily,
        fontFamilyFallback: AppTypography.monoFamilyFallback,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w600,
        color: scheme.onSurfaceVariant,
      ),
      dataTextStyle: textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
      dividerThickness: 1,
      headingRowHeight: 36,
      dataRowMinHeight: 40,
      dataRowMaxHeight: 44,
    ),
    switchTheme: SwitchThemeData(
      // 几何无法经 SwitchThemeData 直角化（工位内一律用
      // WorkstationToggle/WorkstationSwitch）；此处在配色上对齐直角开关：
      // 选中轨道 onSurface 时滑块必须取反色 surface，否则与轨道同色不可见。
      trackOutlineColor: WidgetStatePropertyAll(scheme.outline),
      trackOutlineWidth: const WidgetStatePropertyAll(1),
      thumbColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? scheme.surface
            : scheme.outline;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return scheme.onSurface;
        }
        return scheme.surfaceContainerHighest;
      }),
    ),
  );
}

OutlineInputBorder _outlineInputBorder(Color color) {
  return OutlineInputBorder(
    borderRadius: BorderRadius.zero,
    borderSide: BorderSide(color: color, width: 1),
  );
}
