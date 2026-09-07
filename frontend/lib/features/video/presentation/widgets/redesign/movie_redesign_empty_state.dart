import 'package:flutter/material.dart';
import 'package:omninest/features/video/presentation/theme/movie_redesign_theme.dart';

/// 新版空态：居中图标 + 主文案 + 等宽副文案。
class MovieRedesignEmptyState extends StatelessWidget {
  const MovieRedesignEmptyState({
    required this.icon,
    required this.title,
    this.subtitle,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = context.movieRedesign;
    final text = context.movieRedesignText;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 80),
      child: Column(
        children: [
          Icon(
            icon,
            size: 32,
            color: palette.mutedForeground.withValues(alpha: 0.40),
          ),
          const SizedBox(height: 12),
          Text(title, style: text.body(size: 14, weight: FontWeight.w500)),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: text.mono(
                size: 12,
                color: palette.mutedForeground.withValues(alpha: 0.70),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
