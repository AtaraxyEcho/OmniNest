import 'package:flutter/material.dart';

/// 全局搜索命令面板色板（Ctrl+K）。
///
/// 按 OmniNest Command Palette 设计稿钉死的双主题色板：浅色为纸感
/// F7F8F6 基调，深色为架构终端 0D1117 基调；不随全局主题派生。
@immutable
class CommandPaletteColors extends ThemeExtension<CommandPaletteColors> {
  const CommandPaletteColors({
    required this.isDark,
    required this.canvas,
    required this.surface,
    required this.surfaceSub,
    required this.surfaceMuted,
    required this.surfaceActive,
    required this.ink,
    required this.inkMuted,
    required this.inkPlaceholder,
    required this.icon,
    required this.hairline,
    required this.border,
    required this.accent,
    required this.statusOk,
    required this.kbdBg,
    required this.kbdBorder,
    required this.scrim,
    required this.panelShadow,
  });

  const CommandPaletteColors.light()
    : isDark = false,
      canvas = const Color(0xFFF7F8F6),
      surface = const Color(0xFFFFFFFF),
      surfaceSub = const Color(0xFFF7F9F7),
      surfaceMuted = const Color(0xFFF0F2EF),
      surfaceActive = const Color(0xFFE7EAE6),
      ink = const Color(0xFF1A1D1B),
      inkMuted = const Color(0xFF58605B),
      inkPlaceholder = const Color(0xFF8A938D),
      icon = const Color(0xFF58605B),
      hairline = const Color(0xFFE2E8F0),
      border = const Color(0xFFD2D7D2),
      accent = const Color(0xFF0B6B61),
      statusOk = const Color(0xFF217A45),
      kbdBg = const Color(0xFFF0F2EF),
      kbdBorder = const Color(0xFFD2D7D2),
      scrim = const Color(0xCCF7F8F6),
      panelShadow = true;

  const CommandPaletteColors.dark()
    : isDark = true,
      canvas = const Color(0xFF0D1117),
      surface = const Color(0xFF161B22),
      surfaceSub = const Color(0xFF161B22),
      surfaceMuted = const Color(0xFF1F242C),
      surfaceActive = const Color(0xFF21262D),
      ink = const Color(0xFFEDEDED),
      inkMuted = const Color(0xFF8B949E),
      inkPlaceholder = const Color(0xFF484F58),
      icon = const Color(0xFF94A3B8),
      hairline = const Color(0xFF30363D),
      border = const Color(0xFF30363D),
      accent = const Color(0xFF79D6C8),
      statusOk = const Color(0xFF10B981),
      kbdBg = const Color(0xFF1F242C),
      kbdBorder = const Color(0xFF30363D),
      scrim = const Color(0xCC0D1117),
      panelShadow = false;

  final bool isDark;
  final Color canvas;
  final Color surface;
  final Color surfaceSub;
  final Color surfaceMuted;
  final Color surfaceActive;
  final Color ink;
  final Color inkMuted;
  final Color inkPlaceholder;
  final Color icon;
  final Color hairline;
  final Color border;
  final Color accent;
  final Color statusOk;
  final Color kbdBg;
  final Color kbdBorder;
  final Color scrim;

  /// 浅色主题保留面板投影，深色主题靠描边分层。
  final bool panelShadow;

  @override
  CommandPaletteColors copyWith({
    bool? isDark,
    Color? canvas,
    Color? surface,
    Color? surfaceSub,
    Color? surfaceMuted,
    Color? surfaceActive,
    Color? ink,
    Color? inkMuted,
    Color? inkPlaceholder,
    Color? icon,
    Color? hairline,
    Color? border,
    Color? accent,
    Color? statusOk,
    Color? kbdBg,
    Color? kbdBorder,
    Color? scrim,
    bool? panelShadow,
  }) {
    return CommandPaletteColors(
      isDark: isDark ?? this.isDark,
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceSub: surfaceSub ?? this.surfaceSub,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      surfaceActive: surfaceActive ?? this.surfaceActive,
      ink: ink ?? this.ink,
      inkMuted: inkMuted ?? this.inkMuted,
      inkPlaceholder: inkPlaceholder ?? this.inkPlaceholder,
      icon: icon ?? this.icon,
      hairline: hairline ?? this.hairline,
      border: border ?? this.border,
      accent: accent ?? this.accent,
      statusOk: statusOk ?? this.statusOk,
      kbdBg: kbdBg ?? this.kbdBg,
      kbdBorder: kbdBorder ?? this.kbdBorder,
      scrim: scrim ?? this.scrim,
      panelShadow: panelShadow ?? this.panelShadow,
    );
  }

  @override
  CommandPaletteColors lerp(CommandPaletteColors? other, double t) {
    if (other == null) {
      return this;
    }
    return t < 0.5 ? this : other;
  }
}

extension CommandPaletteContext on BuildContext {
  /// 当前主题下的命令面板色板。
  CommandPaletteColors get commandPaletteColors =>
      Theme.of(this).extension<CommandPaletteColors>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? const CommandPaletteColors.dark()
          : const CommandPaletteColors.light());
}
