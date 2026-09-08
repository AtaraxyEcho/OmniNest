import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/feature/video_colors.dart';

class MovieDetailBackButton extends StatelessWidget {
  const MovieDetailBackButton({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      key: const Key('movieDetailBackButton'),
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: context.videoColors.onSurface,
        backgroundColor: context.videoColors.surfaceContainerHigh.withValues(
          alpha: 0.72,
        ),
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
      icon: const Icon(Icons.arrow_back_rounded, size: 18),
      label: Text(AppLocalizations.of(context).videoBackToLibrary),
    );
  }
}

class MovieSectionHeading extends StatelessWidget {
  const MovieSectionHeading({
    required this.title,
    required this.subtitle,
    super.key,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: context.videoColors.onSurface,
                  fontSize: 24,
                  height: 32 / 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: context.videoColors.onSurfaceVariant,
                  fontSize: 14,
                  height: 20 / 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class MovieNoticePanel extends StatelessWidget {
  const MovieNoticePanel({
    required this.icon,
    required this.title,
    required this.message,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.videoColors.primaryContainer.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: context.videoColors.primary.withValues(alpha: 0.24),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: context.videoColors.primary),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: context.videoColors.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  message,
                  style: TextStyle(
                    color: context.videoColors.onSurfaceVariant,
                    fontSize: 13,
                    height: 18 / 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class EmptyMovieState extends StatelessWidget {
  const EmptyMovieState({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(42),
      decoration: BoxDecoration(
        color: context.videoColors.surfaceContainerHigh.withValues(alpha: 0.66),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: context.videoColors.outlineVariant.withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.movie_creation_outlined,
            color: context.videoColors.primary,
            size: 42,
          ),
          SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(
              color: context.videoColors.onSurfaceVariant,
              fontSize: 14,
              height: 20 / 14,
            ),
          ),
        ],
      ),
    );
  }
}

/// 通用状态色点：任务、来源等状态的圆形指示。
class StatusDot extends StatelessWidget {
  const StatusDot({required this.color, this.size = 8, super.key});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
