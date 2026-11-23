import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/desktop/desktop_palette.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/app/theme/feature/files_colors.dart';
import 'package:omninest/app/theme/feature/music_colors.dart';
import 'package:omninest/app/theme/feature/photos_colors.dart';
import 'package:omninest/app/theme/feature/reader_colors.dart';
import 'package:omninest/app/theme/feature/video_colors.dart';
import 'package:omninest/app/theme/global_theme_colors.dart';
import 'package:omninest/core/window/window_chrome_controller.dart';

/// 桌面/Web 端主题装配。
///
/// 两件事一次做完：
/// 1. 把样例色板映射进 [GlobalThemeColors]，让**存量模块页**在不改代码的
///    前提下换成新语言；
/// 2. 各模块 ThemeExtension 一律由**同一份**色板派生（不再各取各的强调
///    色），这是「一个产品一套壳」在颜色层的落点——模块间的割裂感主要
///    来自每模块一套强调色。
abstract final class DesktopTheme {
  /// 按 `(isDark, accent, fontScale)` 缓存已装配的 [ThemeData]，确保路由
  /// 切换时零重复构图、不触发全应用 `Theme.of` 依赖者重建。
  static final Map<(bool, DesktopAccent, double), ThemeData> _cache = {};

  /// 已向 Windows 原生窗口同步过的亮暗状态，用于跨重建去重。
  static bool? _lastSyncedIsDark;

  /// 待在当前帧提交后同步到原生窗口的目标亮暗状态。
  static bool? _pendingSyncIsDark;

  /// 是否已登记本帧的 post-frame 同步回调，避免同帧重复挂载。
  static bool _postFrameSyncScheduled = false;

  /// 将亮暗同步移出 `build()` 同步路径，延迟到帧末执行并跨帧去重，
  /// 避免窗口销毁期在构建阶段直接发起原生 MethodChannel 调用。
  static void scheduleNativeBrightnessSync({required bool isDark}) {
    if (_lastSyncedIsDark == isDark && _pendingSyncIsDark == null) {
      return;
    }
    _pendingSyncIsDark = isDark;
    if (_postFrameSyncScheduled) {
      return;
    }
    _postFrameSyncScheduled = true;
    try {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _postFrameSyncScheduled = false;
        final target = _pendingSyncIsDark;
        _pendingSyncIsDark = null;
        if (target == null || _lastSyncedIsDark == target) {
          return;
        }
        _lastSyncedIsDark = target;
        unawaited(setThemeBrightness(isDark: target));
      });
    } on Object {
      // 纯单元测试未初始化 WidgetsBinding 时跳过原生窗口亮度同步。
      _postFrameSyncScheduled = false;
      _pendingSyncIsDark = null;
    }
  }

  static ThemeData resolve({
    required bool isDark,
    DesktopAccent accent = DesktopAccent.sage,
    double fontScale = 1,
  }) {
    scheduleNativeBrightnessSync(isDark: isDark);
    final cacheKey = (isDark, accent, fontScale);
    final cached = _cache[cacheKey];
    if (cached != null) {
      return cached;
    }
    final skin = DesktopSkin.resolve(isDark: isDark, accent: accent);
    final colors = _globalColors(skin);
    final base = OmniNestTheme.from(
      colors,
      musicColors: MusicColors.fromGlobal(colors),
      videoColors: VideoColors.fromGlobal(colors),
      readerColors: ReaderColors.fromGlobal(colors),
      photosColors: PhotosColors.fromGlobal(colors),
      filesColors: FilesColors.fromGlobal(colors),
    );
    final resolved = base.copyWith(
      scaffoldBackgroundColor: skin.bg,
      canvasColor: skin.bg,
      splashFactory: NoSplash.splashFactory,
      textTheme: _textTheme(base.textTheme, skin, fontScale),
      primaryTextTheme: _textTheme(base.primaryTextTheme, skin, fontScale),
      sliderTheme: SliderThemeData(
        activeTrackColor: skin.accent,
        inactiveTrackColor: skin.raise3,
        disabledActiveTrackColor: skin.accent.withValues(alpha: 0.32),
        disabledInactiveTrackColor: skin.raise3.withValues(alpha: 0.54),
        thumbColor: DesktopPalette.onStage,
        disabledThumbColor: skin.text3,
        overlayColor: skin.accentWash(0.22),
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(
          enabledThumbRadius: 6,
          elevation: 1,
          pressedElevation: 1,
        ),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 13),
        trackShape: const RoundedRectSliderTrackShape(),
        showValueIndicator: ShowValueIndicator.never,
      ),
      dividerTheme: DividerThemeData(
        color: skin.line,
        thickness: DesktopMetrics.hairline,
        space: DesktopMetrics.hairline,
      ),
      // 样例 polish.css 的统一滚动条：12px 轨道、透明边距托出胶囊滑块，
      // 悬停染强调色。浏览器默认滚动条会立刻把界面拉回「网页控件」观感。
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.hovered) ||
                      states.contains(WidgetState.dragged)
                  ? 6.0
                  : 4.5,
        ),
        radius: const Radius.circular(DesktopMetrics.radiusPill),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.dragged)) {
            return skin.accent;
          }
          if (states.contains(WidgetState.hovered)) {
            return Color.lerp(
              skin.accent,
              skin.text,
              0.125,
            )!.withValues(alpha: 0.80);
          }
          return skin.text.withValues(alpha: 0.16);
        }),
        trackVisibility: const WidgetStatePropertyAll(false),
        interactive: true,
        minThumbLength: 36,
      ),
      tooltipTheme: base.tooltipTheme.copyWith(
        decoration: BoxDecoration(
          color: skin.pop,
          borderRadius: BorderRadius.circular(DesktopMetrics.radiusSmall),
          border: Border.all(color: skin.line2),
        ),
        textStyle: DesktopType.caption(skin.text),
      ),
      extensions: [...base.extensions.values, skin],
    );
    _cache[cacheKey] = resolved;
    return resolved;
  }

  static GlobalThemeColors _globalColors(DesktopSkin skin) {
    final solid = skin.panelSolid;
    Color wash(Color seed, double fraction) =>
        Color.lerp(solid, seed, fraction)!;
    return GlobalThemeColors(
      surface: skin.bg,
      surfaceContainerLowest: skin.bg,
      surfaceContainerLow: skin.bg2,
      surfaceContainer: solid,
      surfaceContainerHigh: Color.lerp(solid, skin.text, 0.05)!,
      surfaceContainerHighest: Color.lerp(solid, skin.text, 0.10)!,
      onSurface: skin.text,
      onSurfaceVariant: skin.text2,
      primary: skin.accent,
      primaryContainer: wash(skin.accent, 0.18),
      onPrimary: skin.accentInk,
      onPrimaryContainer: skin.accent,
      secondary: skin.text2,
      secondaryContainer: wash(skin.text2, 0.14),
      tertiary: skin.warm,
      tertiaryContainer: wash(skin.warm, 0.18),
      error: skin.bad,
      onError: DesktopPalette.accentInkLight,
      outline: skin.text3,
      outlineVariant: Color.lerp(solid, skin.text, 0.16)!,
      accentWarm: skin.warm,
      accentCool: skin.info,
      success: skin.ok,
      warning: skin.warn,
      info: skin.info,
      hoverOverlay: skin.accentWash(0.10),
      selectedOverlay: skin.accentWash(0.16),
      focusRing: skin.accentWash(0.70),
      overlay: DesktopPalette.stageBlack.withValues(alpha: 0.50),
      overlayLight: skin.raise2,
      shadow: skin.shadow.first.color,
      star: skin.warn,
      badgeBg: skin.accent,
      badgeText: skin.accentInk,
    );
  }

  static TextTheme _textTheme(TextTheme base, DesktopSkin skin, double scale) {
    TextStyle sized(TextStyle? source, double size, Color color) {
      return (source ?? const TextStyle()).copyWith(
        fontFamily: DesktopType.uiFamily,
        fontFamilyFallback: DesktopType.uiFallback,
        fontSize: size * scale,
        color: color,
      );
    }

    return base.copyWith(
      displayLarge: sized(
        base.displayLarge,
        DesktopType.sizeDisplay,
        skin.text,
      ).copyWith(fontFamily: DesktopType.serifFamily),
      displayMedium: sized(
        base.displayMedium,
        DesktopType.sizeStat,
        skin.text,
      ).copyWith(fontFamily: DesktopType.serifFamily),
      displaySmall: sized(
        base.displaySmall,
        DesktopType.sizeSection,
        skin.text,
      ).copyWith(fontFamily: DesktopType.serifFamily),
      headlineLarge: sized(
        base.headlineLarge,
        DesktopType.sizeSection,
        skin.text,
      ),
      headlineMedium: sized(
        base.headlineMedium,
        DesktopType.sizeDisplaySm,
        skin.text,
      ),
      headlineSmall: sized(
        base.headlineSmall,
        DesktopType.sizeTitle,
        skin.text,
      ),
      titleLarge: sized(
        base.titleLarge,
        DesktopType.sizePanelTitle,
        skin.text,
      ).copyWith(fontWeight: FontWeight.w600),
      titleMedium: sized(
        base.titleMedium,
        DesktopType.sizeMedium,
        skin.text,
      ).copyWith(fontWeight: FontWeight.w600),
      titleSmall: sized(
        base.titleSmall,
        DesktopType.sizeBase,
        skin.text,
      ).copyWith(fontWeight: FontWeight.w500),
      bodyLarge: sized(base.bodyLarge, DesktopType.sizeBase, skin.text),
      bodyMedium: sized(base.bodyMedium, DesktopType.sizeBody, skin.text),
      bodySmall: sized(base.bodySmall, DesktopType.sizeSmallPlus, skin.text2),
      labelLarge: sized(
        base.labelLarge,
        DesktopType.sizeBody,
        skin.text,
      ).copyWith(fontWeight: FontWeight.w500),
      labelMedium: sized(base.labelMedium, DesktopType.sizeSmall, skin.text2),
      labelSmall: sized(base.labelSmall, DesktopType.sizeCaption, skin.text3),
    );
  }
}
