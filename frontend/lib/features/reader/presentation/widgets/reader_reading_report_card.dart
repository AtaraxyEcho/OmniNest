import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/reader_colors.dart';
import 'package:omninest/core/widgets/workbench_panel.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';

/// 阅读报告统计卡片，展示今日时长、本周时长、连续天数、阅读书籍数。
class ReadingReportCard extends StatelessWidget {
  const ReadingReportCard({this.stats, super.key});

  final ReaderReadingStats? stats;

  @override
  Widget build(BuildContext context) {
    final rc = context.readerColors;
    final todayMinutes = stats?.totalMinutesToday ?? 0;
    final weekMinutes = stats?.totalMinutesThisWeek ?? 0;
    final streak = stats?.currentStreak ?? 0;
    final books = stats?.totalBooksRead ?? 0;

    return WorkbenchPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: rc.tertiary.withValues(alpha: 0.16),
                ),
                child: Icon(Icons.trending_up, color: rc.tertiary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  AppLocalizations.of(context).readerReadingReport,
                  style: TextStyle(
                    color: rc.onSurface,
                    fontSize: AppTypography.bodyLarge,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _StatItem(
                label: AppLocalizations.of(context).readerStatsToday,
                value: _formatMinutes(context, todayMinutes),
                color: rc.tertiary,
              ),
              _StatItem(
                label: AppLocalizations.of(context).readerStatsWeek,
                value: _formatMinutes(context, weekMinutes),
                color: rc.onSurface,
              ),
              _StatItem(
                label: AppLocalizations.of(context).readerStatsStreak,
                value: AppLocalizations.of(context).readerStatsDays(streak),
                color: rc.tertiary,
              ),
              _StatItem(
                label: AppLocalizations.of(context).readerStatsBooks,
                value: '$books',
                color: rc.onSurfaceVariant,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatMinutes(BuildContext context, int minutes) {
    final l10n = AppLocalizations.of(context);
    if (minutes < 60) return l10n.readerStatsMinutes(minutes);
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m > 0
        ? l10n.readerStatsHoursMinutes(h, m)
        : l10n.readerStatsHours(h);
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: AppTypography.titleMedium,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: context.readerColors.onSurfaceVariant,
              fontSize: AppTypography.labelSmall,
            ),
          ),
        ],
      ),
    );
  }
}
