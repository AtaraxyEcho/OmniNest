import 'package:flutter/material.dart';
import 'package:omninest/app/theme/global_theme_colors.dart';

@immutable
class VideoColors extends ThemeExtension<VideoColors> {
  const VideoColors({
    required this.surface,
    required this.surfaceContainerLow,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
    required this.primary,
    required this.primaryContainer,
    required this.onPrimary,
    required this.onPrimaryContainer,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.tertiary,
    required this.outlineVariant,
    required this.playerBarBg,
    required this.subtitleBg,
    required this.playerControlForeground,
    required this.playerControlMuted,
    required this.playerControlHover,
    required this.playerTimelinePlayed,
    required this.playerTimelineBuffered,
    required this.playerTimelineInactive,
    required this.playerPanelSurface,
    required this.playerFocusRing,
  });

  final Color surface;
  final Color surfaceContainerLow;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color surfaceContainerHighest;
  final Color primary;
  final Color primaryContainer;
  final Color onPrimary;
  final Color onPrimaryContainer;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color tertiary;
  final Color outlineVariant;
  final Color playerBarBg;
  final Color subtitleBg;
  final Color playerControlForeground;
  final Color playerControlMuted;
  final Color playerControlHover;
  final Color playerTimelinePlayed;
  final Color playerTimelineBuffered;
  final Color playerTimelineInactive;
  final Color playerPanelSurface;
  final Color playerFocusRing;

  /// 从全局主题色派生 Video 模块专属色
  factory VideoColors.fromGlobal(GlobalThemeColors base) {
    return VideoColors(
      surface: base.surface,
      surfaceContainerLow: base.surfaceContainerLow,
      surfaceContainer: base.surfaceContainer,
      surfaceContainerHigh: base.surfaceContainerHigh,
      surfaceContainerHighest: base.surfaceContainerHighest,
      primary: base.primary,
      primaryContainer: base.primaryContainer,
      onPrimary: base.onPrimary,
      onPrimaryContainer: base.onPrimaryContainer,
      onSurface: base.onSurface,
      onSurfaceVariant: base.onSurfaceVariant,
      tertiary: base.accentWarm,
      outlineVariant: base.outlineVariant,
      playerBarBg: const Color(0xD909090B),
      subtitleBg: const Color(0x99000000),
      playerControlForeground: const Color(0xFFF7F7F8),
      playerControlMuted: const Color(0xB8FFFFFF),
      playerControlHover: const Color(0x24FFFFFF),
      playerTimelinePlayed: const Color(0xFFF7F7F8),
      playerTimelineBuffered: const Color(0x73FFFFFF),
      playerTimelineInactive: const Color(0x2BFFFFFF),
      playerPanelSurface: const Color(0xFF171719),
      playerFocusRing: const Color(0xFFE7E7EA),
    );
  }

  static const List<VideoColors> values = [];

  @override
  VideoColors copyWith({
    Color? surface,
    Color? surfaceContainerLow,
    Color? surfaceContainer,
    Color? surfaceContainerHigh,
    Color? surfaceContainerHighest,
    Color? primary,
    Color? primaryContainer,
    Color? onPrimary,
    Color? onPrimaryContainer,
    Color? onSurface,
    Color? onSurfaceVariant,
    Color? tertiary,
    Color? outlineVariant,
    Color? playerBarBg,
    Color? subtitleBg,
    Color? playerControlForeground,
    Color? playerControlMuted,
    Color? playerControlHover,
    Color? playerTimelinePlayed,
    Color? playerTimelineBuffered,
    Color? playerTimelineInactive,
    Color? playerPanelSurface,
    Color? playerFocusRing,
  }) {
    return VideoColors(
      surface: surface ?? this.surface,
      surfaceContainerLow: surfaceContainerLow ?? this.surfaceContainerLow,
      surfaceContainer: surfaceContainer ?? this.surfaceContainer,
      surfaceContainerHigh: surfaceContainerHigh ?? this.surfaceContainerHigh,
      surfaceContainerHighest:
          surfaceContainerHighest ?? this.surfaceContainerHighest,
      primary: primary ?? this.primary,
      primaryContainer: primaryContainer ?? this.primaryContainer,
      onPrimary: onPrimary ?? this.onPrimary,
      onPrimaryContainer: onPrimaryContainer ?? this.onPrimaryContainer,
      onSurface: onSurface ?? this.onSurface,
      onSurfaceVariant: onSurfaceVariant ?? this.onSurfaceVariant,
      tertiary: tertiary ?? this.tertiary,
      outlineVariant: outlineVariant ?? this.outlineVariant,
      playerBarBg: playerBarBg ?? this.playerBarBg,
      subtitleBg: subtitleBg ?? this.subtitleBg,
      playerControlForeground:
          playerControlForeground ?? this.playerControlForeground,
      playerControlMuted: playerControlMuted ?? this.playerControlMuted,
      playerControlHover: playerControlHover ?? this.playerControlHover,
      playerTimelinePlayed: playerTimelinePlayed ?? this.playerTimelinePlayed,
      playerTimelineBuffered:
          playerTimelineBuffered ?? this.playerTimelineBuffered,
      playerTimelineInactive:
          playerTimelineInactive ?? this.playerTimelineInactive,
      playerPanelSurface: playerPanelSurface ?? this.playerPanelSurface,
      playerFocusRing: playerFocusRing ?? this.playerFocusRing,
    );
  }

  @override
  VideoColors lerp(VideoColors? other, double t) {
    if (other is! VideoColors) return this;
    return VideoColors(
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
      primary: Color.lerp(primary, other.primary, t)!,
      primaryContainer:
          Color.lerp(primaryContainer, other.primaryContainer, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      onPrimaryContainer:
          Color.lerp(onPrimaryContainer, other.onPrimaryContainer, t)!,
      onSurface: Color.lerp(onSurface, other.onSurface, t)!,
      onSurfaceVariant:
          Color.lerp(onSurfaceVariant, other.onSurfaceVariant, t)!,
      tertiary: Color.lerp(tertiary, other.tertiary, t)!,
      outlineVariant: Color.lerp(outlineVariant, other.outlineVariant, t)!,
      playerBarBg: Color.lerp(playerBarBg, other.playerBarBg, t)!,
      subtitleBg: Color.lerp(subtitleBg, other.subtitleBg, t)!,
      playerControlForeground:
          Color.lerp(
            playerControlForeground,
            other.playerControlForeground,
            t,
          )!,
      playerControlMuted:
          Color.lerp(playerControlMuted, other.playerControlMuted, t)!,
      playerControlHover:
          Color.lerp(playerControlHover, other.playerControlHover, t)!,
      playerTimelinePlayed:
          Color.lerp(playerTimelinePlayed, other.playerTimelinePlayed, t)!,
      playerTimelineBuffered:
          Color.lerp(playerTimelineBuffered, other.playerTimelineBuffered, t)!,
      playerTimelineInactive:
          Color.lerp(playerTimelineInactive, other.playerTimelineInactive, t)!,
      playerPanelSurface:
          Color.lerp(playerPanelSurface, other.playerPanelSurface, t)!,
      playerFocusRing: Color.lerp(playerFocusRing, other.playerFocusRing, t)!,
    );
  }
}

extension VideoColorsX on BuildContext {
  VideoColors get videoColors => Theme.of(this).extension<VideoColors>()!;
}
