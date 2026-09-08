import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/feature/reader_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/pages/reader_center_page.dart'
    show kReaderSerifFamily;
import 'package:omninest/features/reader/presentation/widgets/reader_page_scaffold.dart';

/// 统计页：统计卡、14 天活动柱状图、书库构成与在读列表。
class ReaderStatsPage extends ConsumerWidget {
  const ReaderStatsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overviewAsync = ref.watch(readerStatsOverviewProvider);
    final rc = context.readerColors;
    return ReaderPageScaffold(
      target: ReaderPageTarget.stats,
      onRefresh: () async {
        ref.invalidate(readerStatsOverviewProvider);
      },
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context).readerStatsTitle,
            style: TextStyle(
              color: rc.onSurface,
              fontSize: MediaQuery.sizeOf(context).width >= 1024 ? 36 : 30,
              height: 1.15,
              fontFamily: kReaderSerifFamily,
              fontStyle: FontStyle.italic,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 16),
          Container(height: 1, color: rc.outlineVariant.withValues(alpha: 0.6)),
        ],
      ),
      child: overviewAsync.when(
        loading:
            () => const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
            ),
        error: (_, _) => const SizedBox.shrink(),
        data: (overview) => _StatsOverview(overview: overview),
      ),
    );
  }
}

class _StatsOverview extends StatelessWidget {
  const _StatsOverview({required this.overview});

  final ReaderStatsOverview overview;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final minutesUnit = l10n.readerStatsMinutes(1).replaceAll('1', '').trim();
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final cards = [
                _StatCard(
                  label: l10n.readerStatsToday,
                  value: '${_todayMinutes(overview)}',
                  unit: minutesUnit,
                ),
                _StatCard(
                  label: l10n.readerStatsWeek,
                  value: '${_weekMinutes(overview)}',
                  unit: minutesUnit,
                ),
                _StatCard(
                  label: l10n.readerStatsStreak,
                  value: '${_streak(overview)}',
                  unit: l10n.readerStatsDayUnit,
                ),
                _StatCard(
                  label: l10n.readerStatsBooksRead,
                  value: '${overview.completedCount}',
                  unit: '',
                ),
              ];
              if (constraints.maxWidth >= 1024) {
                return Row(
                  children: [
                    for (var i = 0; i < cards.length; i++) ...[
                      if (i > 0) const SizedBox(width: 16),
                      Expanded(child: cards[i]),
                    ],
                  ],
                );
              }
              return GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 2.4,
                children: cards,
              );
            },
          ),
          const SizedBox(height: 40),
          _ActivityChart(overview: overview),
          const SizedBox(height: 40),
          _LibraryBreakdown(overview: overview),
          const SizedBox(height: 40),
          _InProgressList(items: overview.inProgressItems),
        ],
      ),
    );
  }

  int _todayMinutes(ReaderStatsOverview overview) {
    if (overview.dailyMinutes.isEmpty) return 0;
    return overview.dailyMinutes.last.minutes;
  }

  int _weekMinutes(ReaderStatsOverview overview) {
    final days = overview.dailyMinutes;
    if (days.isEmpty) return 0;
    final take = days.length >= 7 ? 7 : days.length;
    return days.skip(days.length - take).fold(0, (sum, d) => sum + d.minutes);
  }

  int _streak(ReaderStatsOverview overview) {
    var streak = 0;
    for (final day in overview.dailyMinutes.reversed) {
      if (day.minutes > 0) {
        streak++;
      } else {
        break;
      }
    }
    return streak;
  }
}

/// 统计卡：细边框方块 + 小号大写字标签 + 大号数值。
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.unit,
  });

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final rc = context.readerColors;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(border: Border.all(color: rc.outlineVariant)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: rc.onSurfaceVariant,
                fontSize: 9,
                height: 1.2,
                letterSpacing: 2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: rc.onSurface,
                    fontSize: 30,
                    height: 1,
                    fontFamily: kReaderSerifFamily,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (unit.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Text(
                    unit,
                    style: TextStyle(
                      color: rc.onSurfaceVariant,
                      fontSize: 11,
                      height: 1.2,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 14 天活动柱状图：今日强调色，其余淡墨，悬停/长按显示分钟。
class _ActivityChart extends StatelessWidget {
  const _ActivityChart({required this.overview});

  final ReaderStatsOverview overview;

  @override
  Widget build(BuildContext context) {
    final rc = context.readerColors;
    final l10n = AppLocalizations.of(context);
    final days = overview.dailyMinutes;
    final maxMinutes = days.fold(
      1,
      (max, d) => d.minutes > max ? d.minutes : max,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(child: _SectionLabel(label: l10n.readerStatsActivity)),
            Text(
              l10n.readerStatsLast14,
              style: TextStyle(
                color: rc.onSurfaceVariant,
                fontSize: 9,
                height: 1.2,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < days.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: _DailyBar(
                  day: days[i],
                  heightPct: days[i].minutes / maxMinutes,
                  isToday: i == days.length - 1,
                ),
              ),
            ],
          ],
        ),
        if (days.isNotEmpty)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDay(days.first.date),
                style: TextStyle(
                  color: rc.onSurfaceVariant,
                  fontSize: 9,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                _formatDay(days.last.date),
                style: TextStyle(
                  color: rc.onSurfaceVariant,
                  fontSize: 9,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
      ],
    );
  }

  String _formatDay(DateTime date) {
    final mm = date.month.toString().padLeft(2, '0');
    final dd = date.day.toString().padLeft(2, '0');
    return '$mm-$dd';
  }
}

class _DailyBar extends StatelessWidget {
  const _DailyBar({
    required this.day,
    required this.heightPct,
    required this.isToday,
  });

  final ReaderDailyMinutes day;
  final double heightPct;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final rc = context.readerColors;
    final tooltip = day.minutes <= 0 ? null : '${day.minutes} min';
    return Tooltip(
      message: tooltip ?? '',
      triggerMode: TooltipTriggerMode.tap,
      child: SizedBox(
        height: 96,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              height: day.minutes <= 0 ? 2 : (96 * heightPct).clamp(4.0, 96.0),
              color:
                  day.minutes <= 0
                      ? rc.outlineVariant
                      : isToday
                      ? rc.reading
                      : rc.onSurface.withValues(alpha: 0.35),
            ),
          ],
        ),
      ),
    );
  }
}

/// 区块标签（大写字距风格）。
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        color: context.readerColors.onSurfaceVariant,
        fontSize: 10,
        height: 1.2,
        letterSpacing: 2.4,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// 书库构成三行：已完成 / 进行中 / 书库总数。
class _LibraryBreakdown extends StatelessWidget {
  const _LibraryBreakdown({required this.overview});

  final ReaderStatsOverview overview;

  @override
  Widget build(BuildContext context) {
    final rc = context.readerColors;
    final l10n = AppLocalizations.of(context);
    final rows = [
      (l10n.readerStatsCompleted, overview.completedCount, overview.totalItems),
      (
        l10n.readerStatsInProgress,
        overview.inProgressCount,
        overview.totalItems,
      ),
      (l10n.readerStatsInLibrary, overview.totalItems, null),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(label: l10n.readerStatsInLibrary),
        const SizedBox(height: 14),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    row.$1,
                    style: TextStyle(
                      color: rc.onSurfaceVariant,
                      fontSize: 13,
                      height: 1.2,
                    ),
                  ),
                ),
                Text(
                  '${row.$2}',
                  style: TextStyle(
                    color: rc.onSurface,
                    fontSize: 13,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (row.$3 != null && row.$3! > 0) ...[
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 96,
                    child: Container(
                      height: 1,
                      color: rc.outlineVariant,
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: (row.$2 / row.$3!).clamp(0.0, 1.0),
                        child: Container(height: 1, color: rc.reading),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// 在读列表：标题作者 + 进度细线 + 百分比。
class _InProgressList extends StatelessWidget {
  const _InProgressList({required this.items});

  final List<ReaderItem> items;

  @override
  Widget build(BuildContext context) {
    final rc = context.readerColors;
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(label: l10n.readerStatsInProgress),
        const SizedBox(height: 14),
        if (items.isEmpty)
          Text(
            l10n.readerEmptyHint,
            style: TextStyle(color: rc.onSurfaceVariant, fontSize: 12),
          )
        else
          for (final item in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: rc.onSurface,
                            fontSize: 13,
                            height: 1.3,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (item.authorName?.isNotEmpty == true)
                          Text(
                            item.authorName!,
                            style: TextStyle(
                              color: rc.onSurfaceVariant,
                              fontSize: 11,
                              height: 1.2,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 80,
                    child: Container(
                      height: 1,
                      color: rc.outlineVariant,
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: (item.progressPercent ?? 0).clamp(
                          0.0,
                          1.0,
                        ),
                        child: Container(height: 1, color: rc.reading),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 34,
                    child: Text(
                      '${((item.progressPercent ?? 0) * 100).round()}%',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: rc.onSurfaceVariant,
                        fontSize: 10,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}
