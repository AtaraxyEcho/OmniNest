part of 'desktop_reader_page.dart';

class _InsightRow extends StatelessWidget {
  const _InsightRow({
    required this.books,
    required this.comics,
    required this.readingHours,
    required this.streakDays,
    required this.columns,
    required this.panelWidth,
    this.dailyReading = const [],
  });

  final int books;
  final int comics;
  final String readingHours;
  final int? streakDays;
  final int columns;
  final double panelWidth;
  final List<ReaderDailyReading> dailyReading;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cards = <(String, String, String)>[
      (l10n.readerStatsBooks, '$books', l10n.readerStatsInLibrary),
      (l10n.readerSegmentComics, '$comics', l10n.readerStatsInLibrary),
      (l10n.readerStatsHoursTitle, readingHours, l10n.readerStatsThisWeek),
      (
        l10n.readerStatsStreak,
        streakDays == null ? '—' : l10n.readerStatsDayCount(streakDays!),
        l10n.readerStatsCurrent,
      ),
    ];
    final skin = DesktopSkin.of(context);
    // 样例 `.insight`：整块是一个玻璃面板（26/28 内距、26 圆角），四张
    // 卡片是面板内的 raise 小格（12/14、14 圆角、无描边），不是四张
    // 各自独立的 panel 卡；面板下半部是 14 天柱图与日期轴。
    final radius = BorderRadius.circular(DesktopMetrics.radiusHero);
    return DesktopGlassSurface(
      borderRadius: radius,
      blur: 20,
      saturation: 1,
      child: Container(
        clipBehavior: Clip.antiAlias,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 26),
        decoration: BoxDecoration(color: skin.panel, borderRadius: radius),
        foregroundDecoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: skin.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (var i = 0; i < cards.length; i++)
                  SizedBox(
                    width: ((panelWidth - 56) - (columns - 1) * 12) / columns,
                    child: DesktopStagger(
                      index: i,
                      child: _InsightCard(
                        label: cards[i].$1,
                        value: cards[i].$2,
                        subtitle: cards[i].$3,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            _ReadingBars(days: dailyReading),
          ],
        ),
      ),
    );
  }
}

/// 样例 `.bars` / `.bar-axis`：14 根柱从底部长起，逐柱交错入场，
/// 悬停展示深色数据气泡并将非悬停柱压暗至 0.4，下方日期轴只标首尾两天。
class _ReadingBars extends StatelessWidget {
  const _ReadingBars({required this.days});

  final List<ReaderDailyReading> days;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    // 后端按契约返回最近 14 天；截取尾部仍可兼容旧服务端返回更长序列。
    // 旧服务端暂时没有数据时仍保留 14 根基线柱，避免右卡片结构塌缩。
    final visibleDays =
        days.length > 14 ? days.sublist(days.length - 14) : days;
    final chartDays = <ReaderDailyReading?>[
      ...List<ReaderDailyReading?>.filled(
        math.max(0, 14 - visibleDays.length),
        null,
      ),
      ...visibleDays,
    ];
    final peak = visibleDays.fold<int>(
      0,
      (max, day) => math.max(max, day.minutes),
    );
    final scale = peak <= 0 ? 1 : peak;
    final items = <DesktopChartBarItem>[
      for (final day in chartDays)
        DesktopChartBarItem(
          // 原型 `Math.max(4, d * 10)%` 保证无阅读日仍有可见的 4% 基线柱。
          fraction: day == null ? 0.04 : math.max(0.04, day.minutes / scale),
          color: skin.accent,
          secondaryColor: skin.accent.withValues(alpha: 0.35),
          tipTitle: day == null ? null : _shortDate(day.date),
          tipValue:
              day == null
                  ? null
                  : (day.minutes <= 0
                      ? (isZh ? '无阅读' : 'No reading')
                      : '${day.minutes} min'),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.readerStatsLast14, style: DesktopType.eyebrow(skin.text3)),
        const SizedBox(height: 8),
        DesktopInteractiveBarChart(
          items: items,
          height: 90,
          barSpacing: 6,
          minFraction: 0.04,
          stagger: true,
          axisStartLabel:
              visibleDays.isNotEmpty
                  ? _shortDate(visibleDays.first.date)
                  : null,
          axisEndLabel:
              visibleDays.isNotEmpty ? _shortDate(visibleDays.last.date) : null,
          axisLabelStyle: DesktopType.micro(skin.text3),
        ),
      ],
    );
  }

  static String _shortDate(String iso) {
    final parts = iso.split('-');
    if (parts.length < 3) return iso;
    final month = int.tryParse(parts[1]) ?? 0;
    final day = int.tryParse(parts[2]) ?? 0;
    return '$month/$day';
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({
    required this.label,
    required this.value,
    required this.subtitle,
  });

  final String label;
  final String value;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: skin.raise,
        borderRadius: BorderRadius.circular(DesktopMetrics.radiusPop),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: DesktopType.micro(skin.text3)),
          const SizedBox(height: 6),
          Text(value, style: DesktopType.readerStatValue(skin.text)),
          const SizedBox(height: 4),
          Text(subtitle, style: DesktopType.micro(skin.text3)),
        ],
      ),
    );
  }
}
