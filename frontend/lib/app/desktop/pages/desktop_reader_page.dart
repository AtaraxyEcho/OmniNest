import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_router_scope.dart';
import 'package:omninest/app/desktop/desktop_routes.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_cover.dart';
import 'package:omninest/app/desktop/widgets/desktop_error_view.dart';
import 'package:omninest/app/desktop/widgets/desktop_fields.dart';
import 'package:omninest/app/desktop/widgets/desktop_select.dart';
import 'package:omninest/app/desktop/widgets/desktop_skeleton.dart';
import 'package:omninest/app/desktop/widgets/desktop_surfaces.dart';
import 'package:omninest/app/desktop/widgets/desktop_tilt.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/features/reader/reader_dashboard.dart';
import 'package:omninest/features/files/media_import_ui.dart'
    show ImportButtonStyle;
import 'package:omninest/features/reader/presentation/widgets/reader_library_import_action.dart';

/// 桌面阅读页（样例 `Reader.tsx`）。
///
/// 两档视图：Overview 是「继续阅读」大卡 + 洞察卡 + 状态筛选书架；
/// Library 是完整清单（搜索/排序/标签/网格-列表切换）。
part 'desktop_reader_library.dart';

enum DesktopReaderFilter { all, inProgress, finished, unread }

class DesktopReaderPage extends ConsumerStatefulWidget {
  const DesktopReaderPage({super.key});

  @override
  ConsumerState<DesktopReaderPage> createState() => _DesktopReaderPageState();
}

enum _ReaderView { overview, library }

class _DesktopReaderPageState extends ConsumerState<DesktopReaderPage> {
  DesktopReaderFilter _filter = DesktopReaderFilter.all;
  _ReaderView _view = _ReaderView.overview;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final centerAsync = ref.watch(readerCenterControllerProvider);
    final center = centerAsync.asData?.value;
    final dashboard = center?.dashboard;
    final readingStats = ref.watch(readerStatsProvider).asData?.value;
    // 加载中/失败都不能退化成「书架还是空的」：dashboard 是非 autoDispose
    // FutureProvider，失败会一直缓存 AsyncError，没有重试入口就永远空态。
    if (dashboard == null && centerAsync.hasError) {
      return DesktopErrorView(
        message: failureToast(
          l10n,
          l10n.readerChapterLoadFailed,
          centerAsync.error ?? l10n.readerChapterLoadFailed,
        ),
        onRetry: () => ref.invalidate(readerCenterControllerProvider),
      );
    }
    if (dashboard == null) {
      return const Center(
        child: SizedBox(
          width: 320,
          child: DesktopSkeletonRows(count: 6, avatar: false),
        ),
      );
    }
    final items = <ReaderItem>[
      ...?center?.items,
      ...dashboard.recentItems,
      ...dashboard.continueReading,
    ];
    final unique =
        <String, ReaderItem>{
          for (final item in items) item.id: item,
        }.values.toList();

    final current =
        dashboard.continueReading.isNotEmpty
            ? dashboard.continueReading.first
            : (unique.isEmpty ? null : unique.first);

    final books = unique
        .where((item) => !item.isDisplayedAsComic)
        .toList(growable: false);
    final comics = unique
        .where((item) => item.isDisplayedAsComic)
        .toList(growable: false);
    final visible = unique.where(_matches).toList();
    final inProgress =
        unique.where((item) {
          final progress = _progressOf(item);
          return progress > 0 && progress < 90;
        }).length;

    final labels = <DesktopReaderFilter, String>{
      DesktopReaderFilter.all: l10n.desktopFilterAll,
      DesktopReaderFilter.inProgress: l10n.desktopFilterInProgress,
      DesktopReaderFilter.finished: l10n.desktopFilterFinished,
      DesktopReaderFilter.unread: l10n.desktopFilterUnread,
    };

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (_view == _ReaderView.library &&
            notification.metrics.extentAfter < 360 &&
            center?.itemsHasMore == true &&
            center?.itemsLoadingMore != true) {
          unawaited(
            ref.read(readerCenterControllerProvider.notifier).loadMoreItems(),
          );
        }
        return false;
      },
      child: SingleChildScrollView(
        child: DesktopPage(
          topPadding: DesktopMetrics.pageTopPaddingCompact,
          children: [
            DesktopPageHead(
              eyebrow:
                  l10n
                      .desktopReaderHeadline(
                        dashboard.overview.totalItems,
                        inProgress,
                      )
                      .toUpperCase(),
              title: l10n.desktopNavReader,
              subtitle: l10n.desktopReaderSubtitle,
              actions: [
                ReaderLibraryImportAction(
                  style: ImportButtonStyle.outlinedButton,
                  label: l10n.filesImport,
                  buttonBuilder:
                      (context, {required onPressed, required busy}) =>
                          DesktopButton(
                            label: l10n.filesImport,
                            icon: DesktopIcons.upload,
                            variant: DesktopButtonVariant.soft,
                            onPressed: onPressed,
                            busy: busy,
                          ),
                ),
                DesktopSeg<_ReaderView>(
                  options: _ReaderView.values,
                  value: _view,
                  labelOf:
                      (value) =>
                          value == _ReaderView.overview
                              ? l10n.desktopReaderOverview
                              : l10n.desktopReaderLibraryView,
                  small: true,
                  onChanged: (value) => setState(() => _view = value),
                ),
              ],
            ),
            if (_view == _ReaderView.library)
              _ReaderLibrary(
                items: unique,
                loadingMore: center?.itemsLoadingMore ?? false,
                status: _filter,
                onStatus: (value) => setState(() => _filter = value),
                onOpen: _openBook,
              )
            else ...[
              if (current != null)
                _ContinueCard(item: current, onOpen: _openBook),
              _InsightRow(
                books: books.length,
                comics: comics.length,
                readingHours:
                    readingStats == null
                        ? '—'
                        : (readingStats.totalMinutesThisWeek / 60)
                            .toStringAsFixed(1),
                streakDays: readingStats?.currentStreak,
                dailyReading: dashboard.overview.dailyReading,
              ),
              const SizedBox(height: 26),
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: DesktopSeg<DesktopReaderFilter>(
                    options: DesktopReaderFilter.values,
                    value: _filter,
                    small: true,
                    labelOf: (value) => labels[value] ?? '',
                    onChanged: (value) => setState(() => _filter = value),
                  ),
                ),
              ),
              if (visible.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 70),
                  child: Center(
                    child: Text(
                      l10n.desktopReaderEmpty,
                      style: DesktopType.medium(DesktopSkin.of(context).text3),
                    ),
                  ),
                )
              else ...[
                if (books.isNotEmpty)
                  _ShelfSection(
                    title: l10n.readerSegmentBooks,
                    items: books,
                    onOpen: _openBook,
                    onSeeAll: () => setState(() => _view = _ReaderView.library),
                  ),
                if (comics.isNotEmpty)
                  _ShelfSection(
                    title: l10n.readerSegmentComics,
                    items: comics,
                    onOpen: _openBook,
                    onSeeAll: () => setState(() => _view = _ReaderView.library),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  double _progressOf(ReaderItem item) => item.progressPercent ?? 0;

  bool _matches(ReaderItem item) {
    final progress = _progressOf(item);
    return switch (_filter) {
      DesktopReaderFilter.all => true,
      DesktopReaderFilter.inProgress => progress > 0 && progress < 90,
      DesktopReaderFilter.finished => progress >= 90,
      DesktopReaderFilter.unread => progress <= 0,
    };
  }

  void _openBook(ReaderItem item) {
    desktopPush(context, DesktopRoutes.bookDetail(item.id));
  }
}

/// 继续阅读大卡（样例 `.continue`）：纸面封面 + 章节眉标 + 衬线书名 + 引文 + 进度。
class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.item, required this.onOpen});

  final ReaderItem item;
  final ValueChanged<ReaderItem> onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final progress = (item.progressPercent ?? 0).clamp(0, 100);
    return Container(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 44),
      padding: const EdgeInsets.fromLTRB(44, 36, 44, 36),
      decoration: BoxDecoration(
        // 样例 `.continue`：accent 14% 混 panelSolid 的斜向渐变 + 26 圆角。
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(skin.panelSolid, skin.accent, 0.14)!, skin.panel],
        ),
        borderRadius: BorderRadius.circular(DesktopMetrics.radiusHero),
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(DesktopMetrics.radiusHero),
        border: Border.all(color: skin.line2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            // 样例 `.continue`：`grid-template-columns: 220px 1fr`；封面
            // 常态 `rotateY(-18deg) rotateX(3deg)`，hover 收平并上抬 6px。
            width: 220,
            height: 300,
            child: DesktopBookTilt(
              restY: -18,
              restX: 3,
              hoverY: -6,
              hoverX: 0,
              hoverLift: -6,
              child: _BookCover(item: item, large: true),
            ),
          ),
          const SizedBox(width: 44),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.currentChapterTitle == null
                      ? l10n.desktopReaderContinue
                      : '${l10n.desktopReaderContinue} · ${item.currentChapterTitle}',
                  style: DesktopType.eyebrow(skin.text3),
                ),
                const SizedBox(height: 10),
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: DesktopType.displayXl(
                    skin.text,
                    MediaQuery.sizeOf(context).width,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  item.authorName ?? '',
                  style: DesktopType.dense(skin.text2),
                ),
                if ((item.description ?? '').isNotEmpty) ...[
                  const SizedBox(height: 16),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Text(
                      item.description!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: DesktopType.quote(skin.text2),
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: skin.raise3,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: (progress / 100).clamp(0.0, 1.0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: skin.accent,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${progress.round()}%',
                      style: DesktopType.numeric(skin.text3),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    DesktopButton(
                      label: l10n.desktopReaderContinueAction,
                      icon: DesktopIcons.book,
                      variant: DesktopButtonVariant.primary,
                      large: true,
                      onPressed: () => onOpen(item),
                    ),
                    const SizedBox(width: 10),
                    DesktopButton(
                      label: l10n.desktopReaderBookPage,
                      icon: DesktopIcons.info,
                      variant: DesktopButtonVariant.soft,
                      large: true,
                      onPressed: () => onOpen(item),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 洞察行（样例 `.insight` 的 i-cards）：四张统计卡。
class _InsightRow extends StatelessWidget {
  const _InsightRow({
    required this.books,
    required this.comics,
    required this.readingHours,
    required this.streakDays,
    this.dailyReading = const [],
  });

  final int books;
  final int comics;
  final String readingHours;
  final int? streakDays;
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
    return Container(
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 26),
      decoration: BoxDecoration(
        color: skin.panel,
        borderRadius: BorderRadius.circular(DesktopMetrics.radiusHero),
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(DesktopMetrics.radiusHero),
        border: Border.all(color: skin.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 860 ? 4 : 2;
              final width =
                  (constraints.maxWidth - (columns - 1) * 12) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (var i = 0; i < cards.length; i++)
                    SizedBox(
                      width: width,
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
              );
            },
          ),
          if (dailyReading.isNotEmpty) ...[
            const SizedBox(height: 20),
            _ReadingBars(days: dailyReading),
          ],
        ],
      ),
    );
  }
}

/// 样例 `.bars` / `.bar-axis`：14 根柱从底部长起，逐柱交错入场，
/// 下方日期轴只标首尾两天，避免 14 个标签互相挤。
class _ReadingBars extends StatelessWidget {
  const _ReadingBars({required this.days});

  final List<ReaderDailyReading> days;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final peak = days.fold<int>(0, (max, day) => math.max(max, day.minutes));
    final scale = peak <= 0 ? 1 : peak;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 90,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < days.length; i++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: i == days.length - 1 ? 0 : 6,
                    ),
                    child: DesktopStagger(
                      index: i,
                      child: _ReadingBar(
                        fraction: days[i].minutes / scale,
                        color: skin.accent,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _shortDate(days.first.date),
              style: DesktopType.micro(skin.text3),
            ),
            Text(
              _shortDate(days.last.date),
              style: DesktopType.micro(skin.text3),
            ),
          ],
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

class _ReadingBar extends StatelessWidget {
  const _ReadingBar({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: fraction.clamp(0.0, 1.0)),
      duration: MotionToken.resolve(context, MotionToken.chart),
      curve: DesktopMotion.spring,
      builder:
          (context, value, _) => Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: value,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(6),
                    bottom: Radius.circular(3),
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [color, color.withValues(alpha: 0.35)],
                  ),
                ),
              ),
            ),
          ),
    );
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

class _ShelfSection extends StatelessWidget {
  const _ShelfSection({
    required this.title,
    required this.items,
    required this.onOpen,
    required this.onSeeAll,
  });

  final String title;
  final List<ReaderItem> items;
  final ValueChanged<ReaderItem> onOpen;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    return DesktopSection(
      title: title,
      actionLabel: AppLocalizations.of(context).desktopSeeAll,
      onAction: onSeeAll,
      child: _Shelf(items: items, onOpen: onOpen),
    );
  }
}

class _Shelf extends StatelessWidget {
  const _Shelf({required this.items, required this.onOpen});

  final List<ReaderItem> items;
  final ValueChanged<ReaderItem> onOpen;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final target = (MediaQuery.sizeOf(context).width * 0.12).clamp(
          150.0,
          190.0,
        );
        // 样例 `.shelf`：`minmax(clamp(150px,12vw,190px),1fr)` + `gap: 30px 26px`
        // （行距 30、列距 26），列宽要按列距反推，否则最后一列会溢出。
        final columns = ((constraints.maxWidth + 26) / (target + 26))
            .floor()
            .clamp(2, 8);
        final width = (constraints.maxWidth - (columns - 1) * 26) / columns;
        return Wrap(
          spacing: 26,
          runSpacing: 30,
          children: [
            for (var i = 0; i < items.length; i++)
              SizedBox(
                width: width,
                child: DesktopStagger(
                  index: i,
                  child: _BookCard(
                    item: items[i],
                    onTap: () => onOpen(items[i]),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _BookCard extends StatelessWidget {
  const _BookCard({required this.item, required this.onTap});

  final ReaderItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final progress = (item.progressPercent ?? 0).clamp(0, 100);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        DesktopTilt(
          maxDegrees: 5,
          radius: 6,
          onTap: onTap,
          child: AspectRatio(
            aspectRatio: 168 / 240,
            child: _BookCover(item: item),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          item.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: DesktopType.rowTitle(skin.text),
        ),
        const SizedBox(height: 2),
        Text(
          item.authorName ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: DesktopType.caption(skin.text3),
        ),
        if (progress > 0) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 3,
              child: LinearProgressIndicator(
                value: progress / 100,
                backgroundColor: skin.raise3,
                valueColor: AlwaysStoppedAnimation<Color>(skin.accent),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 纸面封面（样例 `.book-cover`）：有封面图就用图，没有就用强调色纸面 + 书名。
class _BookCover extends StatelessWidget {
  const _BookCover({required this.item, this.large = false});

  final ReaderItem item;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    if ((item.coverUrl ?? '').isNotEmpty) {
      return DesktopCover(
        url: item.coverUrl,
        kind: DesktopCoverKind.reader,
        fallbackIcon: DesktopIcons.book,
        cacheKey: 'desktop-reader-${item.id}',
        iconSize: large ? 28 : 20,
      );
    }
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            skin.accent.withValues(alpha: 0.32),
            skin.accent.withValues(alpha: 0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: skin.line),
      ),
      padding: EdgeInsets.all(large ? 18 : 12),
      alignment: Alignment.bottomLeft,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 书脊：左侧一条暗带，纸面才有厚度。
          Container(
            width: 3,
            height: large ? 84 : 56,
            margin: const EdgeInsets.only(bottom: 10),
            color: skin.line2,
          ),
          Text(
            item.title,
            maxLines: large ? 3 : 2,
            overflow: TextOverflow.ellipsis,
            style: DesktopType.cardTitle(skin.text),
          ),
          if ((item.authorName ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              item.authorName!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DesktopType.caption(skin.text3),
            ),
          ],
        ],
      ),
    );
  }
}
