import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omninest/app/desktop/desktop_ambient_hints.dart';
import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_router_scope.dart';
import 'package:omninest/app/desktop/desktop_routes.dart';
import 'package:omninest/app/desktop/desktop_shell_state.dart';
import 'package:omninest/app/desktop/desktop_toast.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_cover.dart';
import 'package:omninest/app/desktop/widgets/desktop_error_view.dart';
import 'package:omninest/app/desktop/widgets/desktop_fields.dart';
import 'package:omninest/app/desktop/widgets/desktop_glass.dart';
import 'package:omninest/app/desktop/widgets/desktop_media_import_dialog.dart';
import 'package:omninest/app/desktop/widgets/desktop_select.dart';
import 'package:omninest/app/desktop/widgets/desktop_skeleton.dart';
import 'package:omninest/app/desktop/widgets/desktop_surfaces.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_palette.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/features/reader/reader_dashboard.dart';
import 'package:omninest/features/reader/application/reader_import_queue_controller.dart';
import 'package:omninest/features/reader/application/reader_controller.dart'
    show readerApiProvider, ReaderCenterState;
import 'package:omninest/features/files/media_import_ui.dart'
    show ImportButtonStyle;
import 'package:omninest/features/reader/presentation/widgets/reader_library_import_action.dart';

/// 桌面阅读页（样例 `Reader.tsx`）。
///
/// 两档视图：Overview 是「继续阅读」大卡 + 洞察卡 + 状态筛选书架；
part 'desktop_reader_insights.dart';

/// Library 是完整清单（搜索/排序/标签/网格-列表切换）。
part 'desktop_reader_library.dart';

enum DesktopReaderFilter { all, inProgress, finished, unread }

class DesktopReaderPage extends ConsumerStatefulWidget {
  const DesktopReaderPage({this.initialLibrary = false, super.key});

  /// 书架深链在桌面复用原型的 Library 视图，移动端仍由独立书架页承载。
  final bool initialLibrary;

  @override
  ConsumerState<DesktopReaderPage> createState() => _DesktopReaderPageState();
}

enum _ReaderView { overview, library }

class _DesktopReaderPageState extends ConsumerState<DesktopReaderPage> {
  DesktopReaderFilter _filter = DesktopReaderFilter.all;
  late _ReaderView _view =
      widget.initialLibrary ? _ReaderView.library : _ReaderView.overview;
  final TextEditingController _librarySearch = TextEditingController();
  _ReaderSort _librarySort = _ReaderSort.recent;
  _ReaderType _libraryType = _ReaderType.all;
  String? _libraryGenre;
  bool _libraryGrid = true;

  @override
  void didUpdateWidget(covariant DesktopReaderPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialLibrary != widget.initialLibrary) {
      _view =
          widget.initialLibrary ? _ReaderView.library : _ReaderView.overview;
    }
  }

  @override
  void dispose() {
    _librarySearch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final centerAsync = ref.watch(readerCenterControllerProvider);
    final center = centerAsync.asData?.value;
    final dashboard = center?.dashboard;
    final readingStats = ref.watch(readerStatsProvider).asData?.value;
    if (dashboard == null && centerAsync.hasError) {
      return DesktopErrorView(
        message: failureToast(
          l10n,
          l10n.readerLibraryLoadFailed,
          centerAsync.error ?? l10n.readerLibraryLoadFailed,
        ),
        onRetry: () => ref.invalidate(readerCenterControllerProvider),
      );
    }

    return DesktopSkeletonSwitcher(
      regionId: 'desktop-reader-home',
      hasData: dashboard != null,
      loading: dashboard == null,
      skeleton: const _ReaderPageSkeleton(),
      child:
          dashboard == null
              ? const SizedBox.shrink()
              : _buildLoadedPage(
                context: context,
                l10n: l10n,
                center: center,
                dashboard: dashboard,
                readingStats: readingStats,
              ),
    );
  }

  Widget _buildLoadedPage({
    required BuildContext context,
    required AppLocalizations l10n,
    required ReaderCenterState? center,
    required ReaderDashboard dashboard,
    required ReaderReadingStats? readingStats,
  }) {
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
    final visibleBooks = visible
        .where((item) => !item.isDisplayedAsComic)
        .toList(growable: false);
    final visibleComics = visible
        .where((item) => item.isDisplayedAsComic)
        .toList(growable: false);
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

    final libraryQuery = _buildReaderLibraryQuery(
      items: unique,
      searchText: _librarySearch.text,
      status: _filter,
      type: _libraryType,
      genre: _libraryGenre,
      sort: _librarySort,
    );

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
      child: DesktopSliverPage(
        topPadding: DesktopMetrics.pageTopPaddingCompact,
        slivers: [
          SliverToBoxAdapter(
            child: DesktopPageHead(
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
                  onPressedOverride: () => unawaited(_openImportDialog()),
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
          ),
          if (_view == _ReaderView.library) ...[
            DesktopStickySliver(
              child: _ReaderLibraryStickyBar(
                search: _librarySearch,
                type: _libraryType,
                sort: _librarySort,
                grid: _libraryGrid,
                onSearchChanged: () => setState(() {}),
                onTypeChanged:
                    (value) => setState(() {
                      _libraryType = value;
                      _libraryGenre = null;
                    }),
                onSortChanged: (value) => setState(() => _librarySort = value),
                onGridChanged: (grid) => setState(() => _libraryGrid = grid),
              ),
            ),
            SliverToBoxAdapter(
              child: _ReaderLibraryBody(
                query: libraryQuery,
                loadingMore: center?.itemsLoadingMore ?? false,
                status: _filter,
                type: _libraryType,
                genre: _libraryGenre,
                grid: _libraryGrid,
                hasSearchNeedle: _librarySearch.text.trim().isNotEmpty,
                onStatus: (value) => setState(() => _filter = value),
                onGenre: (value) => setState(() => _libraryGenre = value),
                onClearFilters:
                    () => setState(() {
                      _librarySearch.clear();
                      _filter = DesktopReaderFilter.all;
                      _libraryType = _ReaderType.all;
                      _libraryGenre = null;
                    }),
                onOpen: _openBook,
                onRead: (item) => unawaited(_openContinueReading(item)),
              ),
            ),
          ] else ...[
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final insights = _InsightRow(
                        books: books.length,
                        comics: comics.length,
                        readingHours:
                            readingStats == null
                                ? '—'
                                : (readingStats.totalMinutesThisWeek / 60)
                                    .toStringAsFixed(1),
                        streakDays: readingStats?.currentStreak,
                        dailyReading: dashboard.overview.dailyReading,
                        columns: constraints.maxWidth >= 860 ? 4 : 2,
                        panelWidth: constraints.maxWidth,
                      );
                      if (current == null) {
                        return insights;
                      }
                      final resume = _ContinueCard(
                        item: current,
                        onContinue: _openContinueReading,
                        onOpen: _openBook,
                      );
                      if (constraints.maxWidth < 900) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            resume,
                            const SizedBox(height: 24),
                            insights,
                          ],
                        );
                      }
                      final insightWidth = math.max(
                        320.0,
                        (constraints.maxWidth - 24) / 2.5,
                      );
                      final insightColumns = insightWidth - 56 >= 860 ? 4 : 2;
                      final alignedInsights = _InsightRow(
                        books: books.length,
                        comics: comics.length,
                        readingHours:
                            readingStats == null
                                ? '—'
                                : (readingStats.totalMinutesThisWeek / 60)
                                    .toStringAsFixed(1),
                        streakDays: readingStats?.currentStreak,
                        dailyReading: dashboard.overview.dailyReading,
                        columns: insightColumns,
                        panelWidth: insightWidth,
                      );
                      return IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: resume),
                            const SizedBox(width: 24),
                            SizedBox(
                              width: insightWidth,
                              child: alignedInsights,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 34),
                ],
              ),
            ),
            DesktopStickySliver(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
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
            ),
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  if (visible.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 70),
                      child: Center(
                        child: Text(
                          l10n.desktopReaderEmpty,
                          style: DesktopType.medium(
                            DesktopSkin.of(context).text3,
                          ),
                        ),
                      ),
                    )
                  else ...[
                    if (visibleBooks.isNotEmpty)
                      _ShelfSection(
                        title: l10n.readerSegmentBooks,
                        items: visibleBooks,
                        onOpen: _openBook,
                        onSeeAll:
                            () => setState(() => _view = _ReaderView.library),
                      ),
                    if (visibleComics.isNotEmpty)
                      _ShelfSection(
                        title: l10n.readerSegmentComics,
                        items: visibleComics,
                        onOpen: _openBook,
                        onSeeAll:
                            () => setState(() => _view = _ReaderView.library),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ],
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

  /// 样例 `ImportDialog(kind:"book")`：先选目录文件/本机文件与目标空间，
  /// 再按来源分派到阅读导入队列或 `/reader/import`。
  Future<void> _openImportDialog() async {
    final l10n = AppLocalizations.of(context);
    final selection = await showDesktopMediaImportDialog(
      context,
      kind: DesktopMediaImportKind.books,
      allowSharedSpace: true,
    );
    if (!mounted || !context.mounted || selection == null) return;
    final suffix =
        selection.space == DesktopImportSpace.shared
            ? l10n.desktopMediaImportSharedTaskSuffix
            : '';
    if (selection.deviceFiles.isNotEmpty) {
      ref
          .read(readerImportQueueProvider.notifier)
          .enqueue(selection.deviceFiles, spaceType: selection.spaceType);
      showDesktopToast(
        context,
        '${l10n.desktopMediaImportQueued(selection.deviceFiles.length)}$suffix',
        icon: DesktopIcons.download,
        actionLabel: l10n.desktopViewTasks,
        onAction:
            () => ref
                .read(desktopShellProvider.notifier)
                .setPanel(DesktopPanel.tasks),
      );
      return;
    }
    var imported = 0;
    for (final fileNodeId in selection.fileNodeIds) {
      try {
        await ref.read(readerApiProvider).importFile(fileNodeId: fileNodeId);
        imported++;
      } on Object catch (error) {
        if (!mounted || !context.mounted) return;
        showDesktopToast(
          context,
          failureToast(l10n, l10n.filesImport, error),
          kind: DesktopToastKind.error,
          icon: DesktopIcons.info,
        );
      }
    }
    if (imported == 0 || !mounted || !context.mounted) return;
    await ref.read(readerCenterControllerProvider.notifier).refresh();
    if (!mounted || !context.mounted) return;
    showDesktopToast(
      context,
      '${l10n.importProcessing(imported)}$suffix',
      kind: DesktopToastKind.success,
      icon: DesktopIcons.check,
    );
  }

  void _rememberReaderAmbient(ReaderItem item) {
    ref
        .read(desktopAmbientHintProvider.notifier)
        .rememberReaderBook(
          item.coverUrl,
          DesktopPalette.bookToneFor(item.id).tone,
        );
  }

  void _openBook(ReaderItem item) {
    _rememberReaderAmbient(item);
    desktopPush(context, DesktopRoutes.bookDetail(item.id));
  }

  Future<void> _openContinueReading(ReaderItem item) async {
    if (item.id.isEmpty) {
      return;
    }
    _rememberReaderAmbient(item);
    final encodedId = Uri.encodeComponent(item.id);
    if (item.isComic) {
      desktopPush(context, '/reader/comics/$encodedId/read');
      return;
    }
    if (item.itemType.toUpperCase() == 'PDF') {
      desktopPush(context, '/reader/pdfs/$encodedId/read');
      return;
    }

    try {
      final detail = await ref
          .read(readerItemDetailProvider(item.id).future)
          .timeout(const Duration(milliseconds: 500));
      if (!mounted) {
        return;
      }
      final chapterId = detail.progress?.chapterId;
      if (chapterId == null || chapterId.isEmpty) {
        _openBook(item);
        return;
      }
      desktopPush(
        context,
        '/reader/items/$encodedId/chapters/${Uri.encodeComponent(chapterId)}',
      );
    } on Exception {
      if (mounted) {
        _openBook(item);
      }
    }
  }
}

/// Reader 首屏骨架：页头 + 继续阅读/洞察双栏占位 + 书架卡片网格。
class _ReaderPageSkeleton extends StatelessWidget {
  const _ReaderPageSkeleton();

  @override
  Widget build(BuildContext context) {
    return DesktopSliverPage(
      topPadding: DesktopMetrics.pageTopPaddingCompact,
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const DesktopSkeletonBox(width: 140, height: 11, radius: 5.5),
              const SizedBox(height: 10),
              const DesktopSkeletonBox(width: 220, height: 32, radius: 8),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 900;
                  const hero = DesktopSkeletonBox(
                    height: 320,
                    radius: DesktopMetrics.radiusHero,
                  );
                  const insight = DesktopSkeletonBox(
                    height: 320,
                    radius: DesktopMetrics.radiusHero,
                    index: 2,
                  );
                  if (wide) {
                    final insightWidth = math.max(
                      320.0,
                      (constraints.maxWidth - 24) / 2.5,
                    );
                    return Row(
                      children: [
                        const Expanded(child: hero),
                        const SizedBox(width: 24),
                        SizedBox(width: insightWidth, child: insight),
                      ],
                    );
                  }
                  return const Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [hero, SizedBox(height: 20), insight],
                  );
                },
              ),
              const SizedBox(height: 34),
              const DesktopSkeletonBox(width: 148, height: 20, radius: 6),
              const SizedBox(height: 16),
              const DesktopSkeletonCardGrid(
                count: 8,
                aspectRatio: 2 / 3,
                minTileWidth: 160,
                spacing: 26,
                runSpacing: 30,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 继续阅读大卡（样例 `.continue`）：纸面封面 + 章节眉标 + 衬线书名 + 引文 + 进度。
class _ContinueCard extends StatelessWidget {
  const _ContinueCard({
    required this.item,
    required this.onContinue,
    required this.onOpen,
  });

  final ReaderItem item;
  final ValueChanged<ReaderItem> onContinue;
  final ValueChanged<ReaderItem> onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final progress = (item.progressPercent ?? 0).clamp(0, 100);
    return Container(
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.fromLTRB(44, 36, 44, 36),
      decoration: BoxDecoration(
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
      child: DesktopHover(
        builder:
            (context, hovered) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 220,
                  height: 300,
                  child: DesktopBookTilt(
                    restY: -18,
                    restX: 3,
                    hoverY: -6,
                    hoverX: 0,
                    hoverLift: -6,
                    hoveredOverride: hovered,
                    child: _BookCover(
                      item: item,
                      large: true,
                      hoveredOverride: hovered,
                    ),
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
                            key: const ValueKey<String>(
                              'desktop-reader-continue',
                            ),
                            label: l10n.desktopReaderContinueAction,
                            icon: DesktopIcons.book,
                            variant: DesktopButtonVariant.primary,
                            large: true,
                            onPressed: () => onContinue(item),
                          ),
                          const SizedBox(width: 10),
                          DesktopButton(
                            key: const ValueKey<String>(
                              'desktop-reader-book-page',
                            ),
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
    return DesktopHover(
      builder: (context, hovered) {
        return AnimatedContainer(
          key: ValueKey<String>('desktop-reader-book-card-${item.id}'),
          duration: MotionToken.reduced(
            context,
            const Duration(milliseconds: 220),
          ),
          curve: Curves.easeOutCubic,
          transformAlignment: Alignment.center,
          transform:
              Matrix4.identity()
                ..translateByDouble(0.0, hovered ? -14.0 : 0.0, 0, 1)
                ..rotateZ(hovered ? -1.2 * math.pi / 180.0 : 0.0)
                ..scaleByDouble(
                  hovered ? 1.022 : 1.0,
                  hovered ? 1.022 : 1.0,
                  1.0,
                  1.0,
                ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                button: true,
                label: item.title,
                child: GestureDetector(
                  onTap: onTap,
                  child: AspectRatio(
                    aspectRatio: 168 / 240,
                    child: _BookCover(item: item, hoveredOverride: hovered),
                  ),
                ),
              ),
              const SizedBox(height: 14),
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
          ),
        );
      },
    );
  }
}

class _BookCover extends StatelessWidget {
  const _BookCover({
    required this.item,
    this.large = false,
    this.hoveredOverride,
  });

  final ReaderItem item;
  final bool large;
  final bool? hoveredOverride;

  @override
  Widget build(BuildContext context) {
    return DesktopReaderBookCover(
      itemId: item.id,
      title: item.title,
      author: item.authorName ?? '',
      coverUrl: item.coverUrl,
      isComic: item.isDisplayedAsComic,
      readerType: item.readerType,
      volumeNumber: item.volumeNumber,
      large: large,
      hoveredOverride: hoveredOverride,
    );
  }
}
