import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/reader_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_page_scaffold.dart';

/// 统计页：统计卡、14 天活动柱状图、书库构成与在读列表。
class ReaderStatsPage extends ConsumerWidget {
  const ReaderStatsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      child: const _ReaderStatsOverviewSection(),
    );
  }
}

/// 统计概览区块。
///
/// 下拉刷新会 invalidate provider，使状态回到「无值 loading」：此时若渲染
/// 正文转圈，就会与壳层的下拉弧同屏，同一件事出现两个动画。因此保留上一份
/// 概览继续展示，只有真正的首屏（从未取到过数据）才出动图指示。
class _ReaderStatsOverviewSection extends ConsumerStatefulWidget {
  const _ReaderStatsOverviewSection();

  @override
  ConsumerState<_ReaderStatsOverviewSection> createState() =>
      _ReaderStatsOverviewSectionState();
}

class _ReaderStatsOverviewSectionState
    extends ConsumerState<_ReaderStatsOverviewSection> {
  ReaderStatsOverview? _lastOverview;

  @override
  Widget build(BuildContext context) {
    final overviewAsync = ref.watch(readerStatsOverviewProvider);
    ref.listen(readerStatsOverviewProvider, (_, next) {
      final value = next.asData?.value;
      if (value != null) {
        _lastOverview = value;
      }
    });
    final overview = overviewAsync.asData?.value ?? _lastOverview;
    if (overview != null) {
      return _StatsOverview(overview: overview, streak: _streakOf(overview));
    }
    if (overviewAsync.hasError) {
      return const SizedBox.shrink();
    }
    return const SizedBox(
      height: 120,
      child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
    );
  }

  /// 连续阅读天数：以后端按 365 天窗口算好的权威值为准。
  ///
  /// 概览只带最近 14 天，本地计数最多也只能到 14 天；权威值取不到时才退回
  /// 本地兜底算法。
  int _streakOf(ReaderStatsOverview overview) {
    final authoritative = ref.watch(readerStatsProvider).asData?.value;
    if (authoritative != null) {
      return authoritative.currentStreak;
    }
    return _localStreak(overview);
  }

  /// 本地兜底：从最近一个有阅读记录的日期往回数。
  ///
  /// 今天还没读不算断档——概览的最后一项就是今天，直接从它开始会在早上把
  /// 连续 30 天显示成 0 天，与后端口径不一致。
  int _localStreak(ReaderStatsOverview overview) {
    final days = overview.dailyMinutes;
    if (days.isEmpty) return 0;
    var streak = 0;
    final startIdx =
        days.last.minutes == 0 && days.length > 1
            ? days.length - 2
            : days.length - 1;
    for (var i = startIdx; i >= 0; i--) {
      if (days[i].minutes > 0) {
        streak++;
      } else {
        break;
      }
    }
    return streak;
  }
}

class _StatsOverview extends StatelessWidget {
  const _StatsOverview({required this.overview, required this.streak});

  final ReaderStatsOverview overview;

  /// 连续阅读天数：由持 Provider 的上层算好传下来。
  final int streak;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final minutesUnit = l10n.readerStatsMinutes(1).replaceAll('1', '').trim();
    return Center(
      child: ConstrainedBox(
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
                    value: '$streak',
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
                // 2×2 行式布局：卡片高度随内容伸缩（GridView 定宽高比在窄屏溢出）。
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: cards[0]),
                        const SizedBox(width: 16),
                        Expanded(child: cards[1]),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(child: cards[2]),
                        const SizedBox(width: 16),
                        Expanded(child: cards[3]),
                      ],
                    ),
                  ],
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
    return Container(
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
              // ignore: font_size_whitelist
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
                  fontSize: AppTypography.headlineLarge,
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
                    fontSize: AppTypography.labelSmall,
                    height: 1.2,
                  ),
                ),
              ],
            ],
          ),
        ],
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
                // ignore: font_size_whitelist
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
                  // ignore: font_size_whitelist
                  fontSize: 9,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                _formatDay(days.last.date),
                style: TextStyle(
                  color: rc.onSurfaceVariant,
                  // ignore: font_size_whitelist
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
        // ignore: font_size_whitelist
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
                      fontSize: AppTypography.bodyMedium,
                      height: 1.2,
                    ),
                  ),
                ),
                Text(
                  '${row.$2}',
                  style: TextStyle(
                    color: rc.onSurface,
                    fontSize: AppTypography.bodyMedium,
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
            style: TextStyle(
              color: rc.onSurfaceVariant,
              fontSize: AppTypography.bodySmall,
            ),
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
                            fontSize: AppTypography.bodyMedium,
                            height: 1.3,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (item.authorName?.isNotEmpty == true)
                          Text(
                            item.authorName!,
                            style: TextStyle(
                              color: rc.onSurfaceVariant,
                              fontSize: AppTypography.labelSmall,
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
                        // ignore: font_size_whitelist
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
