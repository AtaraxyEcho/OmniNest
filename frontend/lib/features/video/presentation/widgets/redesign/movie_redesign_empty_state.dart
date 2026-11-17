import 'package:flutter/material.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/video/presentation/theme/movie_redesign_theme.dart';

/// 新版空态：居中图标 + 主文案 + 副文案，各分区统一无操作按钮。
class MovieRedesignEmptyState extends StatelessWidget {
  const MovieRedesignEmptyState({
    required this.icon,
    required this.title,
    this.subtitle,
    super.key,
  });

  /// 空态锚点，便于测试锁定收束后的实际尺寸。
  static const Key contentKey = Key('movie_redesign_empty_state');

  /// 空态文案最大宽度，约束桌面宽屏下的视觉范围。
  static const double maxWidth = 360;

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = context.movieRedesign;
    final text = context.movieRedesignText;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: maxWidth),
          child: Column(
            key: contentKey,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 32,
                color: palette.mutedForeground.withValues(alpha: 0.40),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: text.body(
                  size: AppTypography.bodyLarge,
                  weight: FontWeight.w500,
                ),
              ),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: text.mono(
                    size: 12,
                    color: palette.mutedForeground.withValues(alpha: 0.70),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
