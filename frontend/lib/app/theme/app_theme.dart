import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/admin_colors.dart';
import 'package:omninest/app/theme/feature/files_colors.dart';
import 'package:omninest/app/theme/feature/music_colors.dart';
import 'package:omninest/app/theme/feature/photos_colors.dart';
import 'package:omninest/app/theme/feature/reader_colors.dart';
import 'package:omninest/app/theme/feature/video_colors.dart';
import 'package:omninest/app/theme/global_theme_colors.dart';

/// 将排版全部 M3 字级的字距归零；未赋值的字级保持 null 交由默认排版合并。
TextTheme _zeroLetterSpacing(TextTheme theme) {
  TextStyle? zero(TextStyle? style) => style?.copyWith(letterSpacing: 0);
  return TextTheme(
    displayLarge: zero(theme.displayLarge),
    displayMedium: zero(theme.displayMedium),
    displaySmall: zero(theme.displaySmall),
    headlineLarge: zero(theme.headlineLarge),
    headlineMedium: zero(theme.headlineMedium),
    headlineSmall: zero(theme.headlineSmall),
    titleLarge: zero(theme.titleLarge),
    titleMedium: zero(theme.titleMedium),
    titleSmall: zero(theme.titleSmall),
    bodyLarge: zero(theme.bodyLarge),
    bodyMedium: zero(theme.bodyMedium),
    bodySmall: zero(theme.bodySmall),
    labelLarge: zero(theme.labelLarge),
    labelMedium: zero(theme.labelMedium),
    labelSmall: zero(theme.labelSmall),
  );
}

class OmniNestTheme {
  const OmniNestTheme._();

  static ThemeData light() => _build(AppThemePalette.light);

  static ThemeData dark() => _build(AppThemePalette.dark);

  static ThemeData from(
    GlobalThemeColors colors, {
    MusicColors? musicColors,
    VideoColors? videoColors,
    ReaderColors? readerColors,
    PhotosColors? photosColors,
    FilesColors? filesColors,
  }) {
    return _build(
      colors,
      musicColors: musicColors,
      videoColors: videoColors,
      readerColors: readerColors,
      photosColors: photosColors,
      filesColors: filesColors,
    );
  }

  static ThemeData _build(
    GlobalThemeColors colors, {
    MusicColors? musicColors,
    VideoColors? videoColors,
    ReaderColors? readerColors,
    PhotosColors? photosColors,
    FilesColors? filesColors,
  }) {
    final brightness = ThemeData.estimateBrightnessForColor(colors.surface);
    // 桌面/桌面浏览器采用紧凑密度，移动端保持触控尺寸。
    final isDesktopDensity =
        kIsWeb ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
    final controlMinHeight = isDesktopDensity ? 38.0 : 44.0;
    final iconMinSize =
        isDesktopDensity ? const Size(36, 36) : const Size(40, 40);
    final inputVerticalPadding = isDesktopDensity ? 10.0 : 12.0;
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: colors.primary,
      onPrimary: colors.onPrimary,
      primaryContainer: colors.primaryContainer,
      onPrimaryContainer: colors.onPrimaryContainer,
      secondary: colors.secondary,
      onSecondary: colors.onPrimary,
      secondaryContainer: colors.secondaryContainer,
      onSecondaryContainer: colors.onPrimaryContainer,
      tertiary: colors.tertiary,
      onTertiary: colors.onPrimary,
      tertiaryContainer: colors.tertiaryContainer,
      onTertiaryContainer: colors.onPrimaryContainer,
      error: colors.error,
      onError: colors.onError,
      surface: colors.surface,
      onSurface: colors.onSurface,
      onSurfaceVariant: colors.onSurfaceVariant,
      outline: colors.outline,
      outlineVariant: colors.outlineVariant,
      surfaceContainerLowest: colors.surfaceContainerLowest,
      surfaceContainerLow: colors.surfaceContainerLow,
      surfaceContainer: colors.surfaceContainer,
      surfaceContainerHigh: colors.surfaceContainerHigh,
      surfaceContainerHighest: colors.surfaceContainerHighest,
    );
    // 显式赋值全部 15 个 M3 角色并统一字距归零：字号取 AppTypography
    // 语义 token（Photos 阶梯定稿），Material 组件与业务排版同源；
    // M3 默认字距（0.1~0.5）按拉丁字形调校，对中文正文与按钮文案产生
    // 松散不齐的观感，随全局一并归零。
    final textTheme = _zeroLetterSpacing(
      ThemeData(brightness: brightness).textTheme
          .merge(
            const TextTheme(
              displayLarge: TextStyle(
                fontSize: AppTypography.displayLarge,
                height: 1.17,
                fontWeight: FontWeight.w700,
              ),
              displayMedium: TextStyle(
                fontSize: AppTypography.displayMedium,
                height: 1.16,
                fontWeight: FontWeight.w400,
              ),
              displaySmall: TextStyle(
                fontSize: AppTypography.displaySmall,
                height: 1.22,
                fontWeight: FontWeight.w400,
              ),
              headlineLarge: TextStyle(
                fontSize: AppTypography.headlineLarge,
                height: 1.25,
                fontWeight: FontWeight.w600,
              ),
              headlineMedium: TextStyle(
                fontSize: AppTypography.headlineMedium,
                height: 1.22,
                fontWeight: FontWeight.w600,
              ),
              headlineSmall: TextStyle(
                fontSize: AppTypography.headlineSmall,
                height: 1.33,
                fontWeight: FontWeight.w600,
              ),
              titleLarge: TextStyle(
                fontSize: AppTypography.titleLarge,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
              titleMedium: TextStyle(
                fontSize: AppTypography.titleMedium,
                height: 1.5,
                fontWeight: FontWeight.w500,
              ),
              titleSmall: TextStyle(
                fontSize: AppTypography.titleSmall,
                height: 1.43,
                fontWeight: FontWeight.w500,
              ),
              bodyLarge: TextStyle(
                fontSize: AppTypography.bodyLarge,
                height: 1.43,
                fontWeight: FontWeight.w400,
              ),
              bodyMedium: TextStyle(
                fontSize: AppTypography.bodyMedium,
                height: 1.4,
                fontWeight: FontWeight.w400,
              ),
              bodySmall: TextStyle(
                fontSize: AppTypography.bodySmall,
                height: 1.33,
                fontWeight: FontWeight.w400,
              ),
              labelLarge: TextStyle(
                fontSize: AppTypography.labelLarge,
                height: 1.14,
                fontWeight: FontWeight.w500,
              ),
              labelMedium: TextStyle(
                fontSize: AppTypography.labelMedium,
                fontWeight: FontWeight.w600,
              ),
              labelSmall: TextStyle(
                fontSize: AppTypography.labelSmall,
                height: 1.27,
                fontWeight: FontWeight.w500,
              ),
            ),
          )
          .apply(
            fontFamily: AppTypography.fontFamily,
            fontFamilyFallback: AppTypography.fontFamilyFallback,
            bodyColor: colors.onSurface,
            displayColor: colors.onSurface,
          ),
    );
    final roundedShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    );
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: colors.outlineVariant),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.surface,
      canvasColor: colors.surface,
      dividerColor: colors.outlineVariant,
      fontFamily: AppTypography.fontFamily,
      textTheme: textTheme,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      primaryTextTheme: textTheme,
      iconTheme: IconThemeData(color: colors.onSurfaceVariant, size: 20),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: colors.primary,
        selectionColor: colors.primary.withValues(alpha: isDark ? 0.32 : 0.22),
        selectionHandleColor: colors.primary,
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: colors.onSurface,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: colors.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: roundedShape.copyWith(
          side: BorderSide(color: colors.outlineVariant),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shape: roundedShape,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: colors.onSurface,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: colors.onSurfaceVariant,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surfaceContainerLow,
        modalBackgroundColor: colors.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceContainerLowest,
        contentPadding: EdgeInsets.symmetric(
          horizontal: 14,
          vertical: inputVerticalPadding,
        ),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: colors.primary, width: 1.5),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: colors.error),
        ),
        labelStyle: TextStyle(color: colors.onSurfaceVariant),
        hintStyle: TextStyle(color: colors.onSurfaceVariant),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
          minimumSize: Size(44, controlMinHeight),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: roundedShape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.onSurface,
          minimumSize: Size(44, controlMinHeight),
          side: BorderSide(color: colors.outline),
          shape: roundedShape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.primary,
          minimumSize: iconMinSize,
          shape: roundedShape,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: colors.onSurfaceVariant,
          minimumSize: iconMinSize,
          shape: roundedShape,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.surfaceContainer,
        selectedColor: colors.primary.withValues(alpha: isDark ? 0.24 : 0.14),
        labelStyle: TextStyle(color: colors.onSurface),
        checkmarkColor: colors.primary,
        side: BorderSide(color: colors.outlineVariant),
        shape: roundedShape,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: colors.onSurfaceVariant,
        textColor: colors.onSurface,
        selectedColor: colors.primary,
        selectedTileColor: colors.selectedOverlay,
        shape: roundedShape,
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: BorderSide(color: colors.outline),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected)
                  ? colors.onPrimary
                  : colors.onSurfaceVariant,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected)
                  ? colors.primary
                  : colors.surfaceContainerHighest,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: colors.primary,
        inactiveTrackColor: colors.surfaceContainerHighest,
        thumbColor: colors.primary,
        overlayColor: colors.primary.withValues(alpha: 0.14),
        trackHeight: 3,
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        height: 68,
        backgroundColor: colors.surfaceContainerLow,
        indicatorColor: colors.primaryContainer,
        labelTextStyle: WidgetStatePropertyAll(textTheme.labelMedium),
      ),
      navigationRailTheme: NavigationRailThemeData(
        elevation: 0,
        backgroundColor: colors.surfaceContainerLow,
        indicatorColor: colors.primaryContainer,
        selectedIconTheme: IconThemeData(color: colors.onPrimaryContainer),
        unselectedIconTheme: IconThemeData(color: colors.onSurfaceVariant),
        selectedLabelTextStyle: TextStyle(color: colors.onSurface),
        unselectedLabelTextStyle: TextStyle(color: colors.onSurfaceVariant),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: colors.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: roundedShape,
        textStyle: textTheme.bodyMedium?.copyWith(color: colors.onSurface),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(colors.surfaceContainerLow),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(roundedShape),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? colors.surfaceContainerHighest : colors.onSurface,
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: TextStyle(
          color: isDark ? colors.onSurface : colors.surface,
          fontSize: 12,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            isDark ? colors.surfaceContainerHighest : colors.onSurface,
        contentTextStyle: TextStyle(
          color: isDark ? colors.onSurface : colors.surface,
        ),
        shape: roundedShape,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(6),
        radius: const Radius.circular(3),
        thumbColor: WidgetStatePropertyAll(
          colors.onSurfaceVariant.withValues(alpha: 0.55),
        ),
        trackColor: WidgetStatePropertyAll(
          colors.surfaceContainerHighest.withValues(alpha: 0.5),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colors.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(colors.surfaceContainerLow),
        dataRowColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colors.primary.withValues(alpha: 0.08);
          }
          if (states.contains(WidgetState.hovered)) {
            return colors.onSurface.withValues(alpha: 0.04);
          }
          return colors.surface;
        }),
        headingTextStyle: textTheme.labelLarge?.copyWith(
          color: colors.onSurface,
          fontWeight: FontWeight.w700,
        ),
        dataTextStyle: textTheme.bodyMedium?.copyWith(color: colors.onSurface),
        dividerThickness: 1,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.primary,
        linearTrackColor: colors.surfaceContainerHighest,
        circularTrackColor: colors.surfaceContainerHighest,
      ),
      extensions: [
        colors,
        AdminColors.fromGlobal(colors),
        musicColors ?? MusicColors.fromGlobal(_musicAccent(colors, isDark)),
        videoColors ?? VideoColors.fromGlobal(_videoAccent(colors, isDark)),
        readerColors ?? ReaderColors.fromGlobal(_readerAccent(colors, isDark)),
        photosColors ?? PhotosColors.fromGlobal(_photosAccent(colors, isDark)),
        filesColors ?? FilesColors.fromGlobal(_filesAccent(colors, isDark)),
      ],
    );
  }

  static GlobalThemeColors _accent(
    GlobalThemeColors base, {
    required Color primary,
    required Color primaryContainer,
    required Color warm,
    required Color cool,
    required bool isDark,
  }) {
    return GlobalThemeColors(
      surface: base.surface,
      surfaceContainerLowest: base.surfaceContainerLowest,
      surfaceContainerLow: base.surfaceContainerLow,
      surfaceContainer: base.surfaceContainer,
      surfaceContainerHigh: base.surfaceContainerHigh,
      surfaceContainerHighest: base.surfaceContainerHighest,
      onSurface: base.onSurface,
      onSurfaceVariant: base.onSurfaceVariant,
      primary: primary,
      primaryContainer: primaryContainer,
      onPrimary: isDark ? const Color(0xFF061513) : Colors.white,
      onPrimaryContainer: base.onPrimaryContainer,
      secondary: base.secondary,
      secondaryContainer: base.secondaryContainer,
      tertiary: cool,
      tertiaryContainer: Color.lerp(base.surfaceContainerHighest, cool, 0.22)!,
      error: base.error,
      onError: base.onError,
      outline: base.outline,
      outlineVariant: base.outlineVariant,
      accentWarm: warm,
      accentCool: cool,
      success: base.success,
      warning: base.warning,
      info: base.info,
      hoverOverlay:
          Color.lerp(Colors.transparent, primary, isDark ? 0.12 : 0.07)!,
      selectedOverlay:
          Color.lerp(Colors.transparent, primary, isDark ? 0.20 : 0.12)!,
      focusRing: Color.lerp(Colors.transparent, primary, isDark ? 0.48 : 0.32)!,
      overlay: base.overlay,
      overlayLight: base.overlayLight,
      shadow: base.shadow,
      star: base.star,
      badgeBg: base.badgeBg,
      badgeText: base.badgeText,
    );
  }

  static GlobalThemeColors _readerAccent(GlobalThemeColors base, bool isDark) {
    return _accent(
      base,
      primary: isDark ? const Color(0xFFB8D9C5) : const Color(0xFF2F6B4F),
      primaryContainer:
          isDark ? const Color(0xFF254235) : const Color(0xFFDCEFE4),
      warm: isDark ? const Color(0xFFE4C98D) : const Color(0xFF8E6A28),
      cool: isDark ? const Color(0xFFA8C8D9) : const Color(0xFF3E7188),
      isDark: isDark,
    );
  }

  static GlobalThemeColors _videoAccent(GlobalThemeColors base, bool isDark) {
    return _accent(
      base,
      primary: isDark ? const Color(0xFFFFC2A6) : const Color(0xFF9A3412),
      primaryContainer:
          isDark ? const Color(0xFF4B2418) : const Color(0xFFFFE1D2),
      warm: isDark ? const Color(0xFFF5B97A) : const Color(0xFFB45309),
      cool: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
      isDark: isDark,
    );
  }

  static GlobalThemeColors _musicAccent(GlobalThemeColors base, bool isDark) {
    return _accent(
      base,
      primary: isDark ? const Color(0xFF8BD9D5) : const Color(0xFF176B72),
      primaryContainer:
          isDark ? const Color(0xFF194A4C) : const Color(0xFFD4ECEB),
      warm: isDark ? const Color(0xFFE7A6B4) : const Color(0xFFA33F58),
      cool: isDark ? const Color(0xFFA7CBE0) : const Color(0xFF356F8A),
      isDark: isDark,
    );
  }

  static GlobalThemeColors _photosAccent(GlobalThemeColors base, bool isDark) {
    return _accent(
      base,
      primary: isDark ? const Color(0xFFF2C6A4) : const Color(0xFFB25B24),
      primaryContainer:
          isDark ? const Color(0xFF48301F) : const Color(0xFFFFE7D4),
      warm: isDark ? const Color(0xFFF0C177) : const Color(0xFFB7791F),
      cool: isDark ? const Color(0xFF98D5C3) : const Color(0xFF237865),
      isDark: isDark,
    );
  }

  static GlobalThemeColors _filesAccent(GlobalThemeColors base, bool isDark) {
    return _accent(
      base,
      primary: isDark ? const Color(0xFFA7E4E1) : const Color(0xFF08756F),
      primaryContainer:
          isDark ? const Color(0xFF183D3B) : const Color(0xFFD7F1EF),
      warm: isDark ? const Color(0xFFE5C28B) : const Color(0xFF9A6A16),
      cool: isDark ? const Color(0xFF9EDCE6) : const Color(0xFF247B8A),
      isDark: isDark,
    );
  }
}
