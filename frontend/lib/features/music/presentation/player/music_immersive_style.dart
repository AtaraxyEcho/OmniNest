import 'package:flutter/material.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_typography.dart';

/// Music 沉浸播放器使用的视觉配色。
class MusicImmersivePalette {
  const MusicImmersivePalette({
    required this.background,
    required this.surface,
    required this.surfaceStrong,
    required this.text,
    required this.muted,
    required this.accent,
    required this.accentAlt,
    required this.glow,
  });

  /// 从主题色板派生 UI chrome 配色：编辑视觉窗口的面板与调色盘按此
  /// 映射取色，保证与全局主题观感一致。
  factory MusicImmersivePalette.fromColorScheme(ColorScheme colorScheme) {
    return MusicImmersivePalette(
      background: colorScheme.surface,
      surface: colorScheme.surfaceContainerHigh,
      surfaceStrong: colorScheme.surfaceContainerHighest,
      text: colorScheme.onSurface,
      muted: colorScheme.onSurfaceVariant,
      accent: colorScheme.primary,
      accentAlt: colorScheme.tertiary,
      glow: colorScheme.primary.withValues(alpha: 0.35),
    );
  }

  static const digital = MusicImmersivePalette(
    background: Color(0xFF071016),
    surface: Color(0xA6121D25),
    surfaceStrong: Color(0xD9142029),
    text: Color(0xFFF4F7F5),
    muted: Color(0xB8DDE8E7),
    accent: Color(0xFF9FDBE3),
    accentAlt: Color(0xFFD5C27A),
    glow: Color(0x663D8EA0),
  );

  final Color background;
  final Color surface;
  final Color surfaceStrong;
  final Color text;
  final Color muted;
  final Color accent;
  final Color accentAlt;
  final Color glow;
}

/// 编辑视觉窗口统一复用的深色主题：面板、内嵌表单件与调色盘弹窗固定
/// 按深色渲染，不随宿主主题切换，避免浅色主题下深底浅字混配不可读。
final ThemeData musicVisualEditorDarkTheme = OmniNestTheme.dark();

/// 编辑视觉窗口固定深色调色板：从 [musicVisualEditorDarkTheme] 派生。
final MusicImmersivePalette musicVisualEditorDarkPalette =
    MusicImmersivePalette.fromColorScheme(
      musicVisualEditorDarkTheme.colorScheme,
    );

/// Music 沉浸播放器的减少动态效果适配。
class MusicImmersiveMotion {
  const MusicImmersiveMotion._();

  /// 根据系统辅助功能设置解析动画时长。
  static Duration duration(BuildContext context, Duration value) {
    final disabled = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return disabled ? Duration.zero : value;
  }
}

/// 视觉编辑面板控件的生效范围徽标：提示该参数作用于桌面端、移动端
/// 还是两端通用，避免出现"调了没反应"的参数。
class MusicVisualScopeBadge extends StatelessWidget {
  const MusicVisualScopeBadge({
    required this.palette,
    required this.label,
    super.key,
  });

  final MusicImmersivePalette palette;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: palette.muted,
          fontSize: AppTypography.labelMicro,
          height: 1.4,
        ),
      ),
    );
  }
}
