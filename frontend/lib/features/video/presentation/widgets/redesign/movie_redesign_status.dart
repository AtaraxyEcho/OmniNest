import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/video/presentation/theme/movie_redesign_theme.dart';

/// 条目元数据状态（与后端 metadataStatus 对应）。
enum MovieRedesignStatus { matched, pending, failed }

/// 将后端 metadataStatus 字符串解析为状态枚举，未知值按待刮削处理。
MovieRedesignStatus movieRedesignStatusFrom(String? metadataStatus) {
  switch (metadataStatus?.toUpperCase()) {
    case 'MATCHED':
      return MovieRedesignStatus.matched;
    case 'FAILED':
      return MovieRedesignStatus.failed;
    default:
      return MovieRedesignStatus.pending;
  }
}

/// 状态圆点：海报卡元信息行使用。
class MovieRedesignStatusDot extends StatelessWidget {
  const MovieRedesignStatusDot({required this.status, super.key});

  final MovieRedesignStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      MovieRedesignStatus.matched => MovieRedesignPalette.statusMatched,
      MovieRedesignStatus.pending => MovieRedesignPalette.statusPending,
      MovieRedesignStatus.failed => MovieRedesignPalette.statusFailed,
    };
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// 状态文字徽标：详情等场景使用。
class MovieRedesignStatusLabel extends StatelessWidget {
  const MovieRedesignStatusLabel({required this.status, super.key});

  final MovieRedesignStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (label, color) = switch (status) {
      MovieRedesignStatus.matched => (
        l10n.videoRedesignStatusMatched,
        MovieRedesignPalette.statusMatched,
      ),
      MovieRedesignStatus.pending => (
        l10n.videoRedesignStatusPending,
        MovieRedesignPalette.statusPending,
      ),
      MovieRedesignStatus.failed => (
        l10n.videoRedesignStatusFailed,
        MovieRedesignPalette.statusFailed,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.30)),
        borderRadius: MovieRedesignPalette.borderRadius,
        color: color.withValues(alpha: 0.10),
      ),
      child: Text(
        label,
        // ignore: font_size_whitelist
        style: context.movieRedesignText.mono(size: 10, color: color),
      ),
    );
  }
}
