import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/core/utils/image_decode_width.dart';
import 'package:omninest/features/music/music_portal.dart';
import 'package:omninest/features/reader/reader_cover_ui.dart';
import 'package:omninest/core/widgets/brand_logo.dart';
import 'package:omninest/app/theme/feature/smoke_glass_colors.dart';
part 'portal_visual_surfaces.dart';

class PortalVisualPalette {
  const PortalVisualPalette({
    required this.background,
    required this.surface,
    required this.surfaceStrong,
    required this.clearStructuralSurfaces,
    required this.lightweightSurfaceAlpha,
    required this.structuralAlphaCeiling,
    required this.text,
    required this.muted,
    required this.accent,
    required this.accentAlt,
    required this.glow,
  });

  final Color background;
  final Color surface;
  final Color surfaceStrong;
  final bool clearStructuralSurfaces;
  final double lightweightSurfaceAlpha;
  final double? structuralAlphaCeiling;
  final Color text;
  final Color muted;
  final Color accent;
  final Color accentAlt;
  final Color glow;

  /// 返回结构面板填充色，浅色透明模式仅保留边框和阴影。
  Color structuralSurface({double? alpha}) {
    if (clearStructuralSurfaces) {
      return Colors.transparent;
    }
    return alpha == null
        ? surface
        : surface.withValues(alpha: _resolveStructuralAlpha(alpha));
  }

  /// 返回强调控件填充色，浅色透明模式不叠加任何染色层。
  Color structuralStrongSurface({double? alpha}) {
    if (clearStructuralSurfaces) {
      return Colors.transparent;
    }
    return alpha == null
        ? surfaceStrong
        : surfaceStrong.withValues(alpha: _resolveStructuralAlpha(alpha));
  }

  double _resolveStructuralAlpha(double requested) {
    final ceiling = structuralAlphaCeiling;
    if (ceiling == null || requested <= ceiling) {
      return requested;
    }
    return ceiling;
  }

  static PortalVisualPalette of(
    BuildContext context, {
    bool backdropActive = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    if (scheme.brightness == Brightness.light && backdropActive) {
      return const PortalVisualPalette(
        background: Colors.transparent,
        surface: PortalBackdropGlassColors.surface,
        surfaceStrong: PortalBackdropGlassColors.surfaceStrong,
        clearStructuralSurfaces: false,
        lightweightSurfaceAlpha: 0.18,
        structuralAlphaCeiling: 0.46,
        text: SmokeGlassColors.text,
        muted: PortalBackdropGlassColors.muted,
        accent: SmokeGlassColors.accent,
        accentAlt: SmokeGlassColors.accentAlt,
        glow: PortalBackdropGlassColors.glow,
      );
    }
    if (scheme.brightness == Brightness.light) {
      final background =
          Color.lerp(scheme.surface, scheme.primaryContainer, 0.06)!;
      final surface =
          Color.lerp(scheme.surfaceContainer, scheme.primaryContainer, 0.12)!;
      final surfaceStrong =
          Color.lerp(
            scheme.surfaceContainerHigh,
            scheme.secondaryContainer,
            0.08,
          )!;
      return PortalVisualPalette(
        background: background,
        surface: surface.withValues(alpha: 0.48),
        surfaceStrong: surfaceStrong.withValues(alpha: 0.62),
        clearStructuralSurfaces: true,
        lightweightSurfaceAlpha: 0,
        structuralAlphaCeiling: 0,
        text: scheme.onSurface,
        muted: scheme.onSurfaceVariant,
        accent: scheme.primary,
        accentAlt: scheme.tertiary,
        glow: scheme.primary.withValues(alpha: 0.16),
      );
    }
    if (!backdropActive) {
      // 深色无壁纸（Web / 桌面未启用）：烟熏玻璃色板是按「背后有亮壁纸」
      // 设计的，直接压在近黑舞台上会整体灰暗；回落常规暗色表面
      // （与浅色无壁纸分支同构），文字用主题前景色。
      final background =
          Color.lerp(scheme.surface, scheme.primaryContainer, 0.04)!;
      final surface =
          Color.lerp(scheme.surfaceContainer, scheme.primaryContainer, 0.08)!;
      final surfaceStrong =
          Color.lerp(
            scheme.surfaceContainerHigh,
            scheme.secondaryContainer,
            0.05,
          )!;
      return PortalVisualPalette(
        background: background,
        surface: surface,
        surfaceStrong: surfaceStrong,
        clearStructuralSurfaces: false,
        lightweightSurfaceAlpha: 0.18,
        structuralAlphaCeiling: null,
        text: scheme.onSurface,
        muted: scheme.onSurfaceVariant,
        accent: scheme.primary,
        accentAlt: scheme.tertiary,
        glow: scheme.primary.withValues(alpha: 0.16),
      );
    }
    return const PortalVisualPalette(
      background: SmokeGlassColors.background,
      surface: SmokeGlassColors.surface,
      surfaceStrong: SmokeGlassColors.surfaceStrong,
      clearStructuralSurfaces: false,
      lightweightSurfaceAlpha: 0.36,
      structuralAlphaCeiling: null,
      text: SmokeGlassColors.text,
      muted: SmokeGlassColors.muted,
      accent: SmokeGlassColors.accent,
      accentAlt: SmokeGlassColors.accentAlt,
      glow: SmokeGlassColors.glow,
    );
  }
}

/// Portal 动效工具。
class PortalMotion {
  const PortalMotion._();

  /// 根据系统减少动态效果设置返回动画时长。
  static Duration duration(BuildContext context, Duration value) {
    final disabled = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return disabled ? Duration.zero : value;
  }
}

/// 沉浸模式下可通过指针或键盘焦点唤出的顶栏区域。
class PortalImmersiveTopBarReveal extends StatefulWidget {
  const PortalImmersiveTopBarReveal({
    required this.immersive,
    required this.child,
    this.height = 58,
    super.key,
  });

  final bool immersive;
  final Widget child;
  final double height;

  @override
  State<PortalImmersiveTopBarReveal> createState() =>
      _PortalImmersiveTopBarRevealState();
}

class _PortalImmersiveTopBarRevealState
    extends State<PortalImmersiveTopBarReveal> {
  bool _pointerInside = false;
  bool _focusWithin = false;

  bool get _visible => !widget.immersive || _pointerInside || _focusWithin;

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return Focus(
      key: const ValueKey('portal-immersive-top-bar-focus-region'),
      canRequestFocus: widget.immersive,
      onFocusChange: (focused) {
        if (_focusWithin != focused) {
          setState(() => _focusWithin = focused);
        }
      },
      child: MouseRegion(
        onEnter: (_) => _setPointerInside(true),
        onExit: (_) => _setPointerInside(false),
        child: SizedBox(
          key: const ValueKey('portal-immersive-top-bar'),
          height: widget.height,
          child: ExcludeFocus(
            excluding: widget.immersive && !visible,
            child: IgnorePointer(
              ignoring: widget.immersive && !visible,
              child: AnimatedSlide(
                offset: visible ? Offset.zero : const Offset(0, -0.78),
                duration: PortalMotion.duration(
                  context,
                  const Duration(milliseconds: 220),
                ),
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  opacity: visible ? 1 : 0,
                  duration: PortalMotion.duration(
                    context,
                    const Duration(milliseconds: 180),
                  ),
                  curve: Curves.easeOutCubic,
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _setPointerInside(bool value) {
    if (_pointerInside == value) {
      return;
    }
    setState(() => _pointerInside = value);
  }
}

class PortalVisualPanel extends StatelessWidget {
  const PortalVisualPanel({
    required this.palette,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.lightweight = false,
    this.onTap,
    super.key,
  });

  final PortalVisualPalette palette;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool lightweight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final light = Theme.of(context).brightness == Brightness.light;
    final lightForeground =
        ThemeData.estimateBrightnessForColor(palette.text) == Brightness.light;
    final surfaceColor =
        lightweight
            ? palette.structuralSurface(alpha: palette.lightweightSurfaceAlpha)
            : palette.structuralSurface();
    final borderColor =
        lightForeground
            ? Colors.white.withValues(alpha: lightweight ? 0.13 : 0.18)
            : light
            ? Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: lightweight ? 0.10 : 0.14)
            : Colors.white.withValues(alpha: lightweight ? 0.12 : 0.16);
    final shadowColor = Colors.black.withValues(
      alpha:
          !light
              ? (lightweight ? 0.08 : 0.32)
              : lightForeground
              ? (lightweight ? 0.10 : 0.20)
              : (lightweight ? 0.04 : 0.08),
    );
    // 阴影 blur 半径收敛：最大化后多面板大半径阴影在 GPU 合成成本高，
    // 且 22/36 与视觉层次差异有限。
    final shadowBlur = lightweight ? 10.0 : (light ? 16.0 : 22.0);
    final content = DecoratedBox(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: shadowBlur,
            offset: Offset(0, lightweight ? 4 : (light ? 8 : 12)),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) {
      return content;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: content,
      ),
    );
  }
}

class PortalVisualTopBar extends StatelessWidget {
  const PortalVisualTopBar({
    required this.palette,
    required this.trailing,
    required this.onSearch,
    super.key,
  });

  final PortalVisualPalette palette;
  final List<Widget> trailing;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: 64,
      child: Row(
        children: [
          const BrandLogo(size: 34, radius: 8),
          const SizedBox(width: 12),
          Text(
            'OmniNest',
            style: TextStyle(
              color: palette.text,
              fontSize: AppTypography.titleMedium,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: onSearch,
                    child: Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.centerLeft,
                      decoration: BoxDecoration(
                        color: palette.structuralStrongSurface(alpha: 0.62),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: palette.muted.withValues(alpha: 0.20),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.search_rounded,
                            color: palette.muted,
                            size: 17,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            l10n.portalSearch,
                            style: TextStyle(
                              color: palette.muted,
                              fontSize: AppTypography.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          ...trailing,
        ],
      ),
    );
  }
}
