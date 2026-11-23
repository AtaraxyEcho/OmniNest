import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omninest/app/desktop/desktop_ambient_hints.dart';
import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_import_filter.dart';
import 'package:omninest/app/desktop/desktop_router_scope.dart';
import 'package:omninest/app/desktop/desktop_routes.dart';
import 'package:omninest/app/desktop/desktop_shell_state.dart';
import 'package:omninest/app/desktop/desktop_toast.dart';
import 'package:omninest/app/session/session_epoch.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_cover.dart';
import 'package:omninest/app/desktop/widgets/desktop_media_import_dialog.dart'
    show
        DesktopMediaImportKind,
        DesktopMediaImportSelection,
        showDesktopMediaImportDialog;
import 'package:omninest/app/desktop/widgets/desktop_skeleton.dart';
import 'package:omninest/app/desktop/widgets/desktop_surfaces.dart';
import 'package:omninest/app/desktop/widgets/desktop_tilt.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/app/theme/desktop/desktop_palette.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/features/files/media_import_ui.dart'
    show MediaImportButton, MediaImportButtonState;
import 'package:omninest/features/files/application/file_browser_controller.dart';
import 'package:omninest/features/files/application/media_import_queue_controller.dart';
import 'package:omninest/features/files/application/media_import_service.dart'
    show MediaImportBatchResult;
import 'package:omninest/features/video/application/media_import_task_waiter.dart';
import 'package:omninest/features/video/video_dashboard.dart';

// 一个页面三个部分：浏览骨架、影院轮播、海报与轨道。三块合起来超过
// 单文件 800 行的源码闸门，按职责拆成 part 而不是压行数。
part 'desktop_movies_cinema.dart';
part 'desktop_movies_cards.dart';
part 'desktop_movies_history.dart';
part 'desktop_movies_quick_look.dart';
part 'desktop_movies_slivers.dart';

/// 桌面影视页（样例 `Movies.tsx` 的 `Browse`）。
enum DesktopMoviesTab {
  forYou,
  continueWatching,
  movies,
  series,
  anime,
  favorites,
  watchlist,
  history,
}

const desktopMoviesSegTabs = <DesktopMoviesTab>[
  DesktopMoviesTab.forYou,
  DesktopMoviesTab.movies,
  DesktopMoviesTab.series,
  DesktopMoviesTab.anime,
  DesktopMoviesTab.favorites,
  DesktopMoviesTab.watchlist,
  DesktopMoviesTab.history,
];

class DesktopMoviesPage extends ConsumerStatefulWidget {
  const DesktopMoviesPage({
    this.initialTab = DesktopMoviesTab.forYou,
    super.key,
  });

  final DesktopMoviesTab initialTab;

  @override
  ConsumerState<DesktopMoviesPage> createState() => _DesktopMoviesPageState();
}

/// 侧栏固定区的入口用查询参数直达分区（`/video?section=history`），
/// 桌面页把它映射到自己的分页，移动页仍走原来的 section 枚举。
DesktopMoviesTab desktopMoviesTabFromSection(String? section) {
  return switch (section) {
    'history' => DesktopMoviesTab.history,
    'favorites' => DesktopMoviesTab.favorites,
    'watchlist' => DesktopMoviesTab.watchlist,
    'series' => DesktopMoviesTab.series,
    'anime' => DesktopMoviesTab.anime,
    'library' || 'movies' => DesktopMoviesTab.movies,
    _ => DesktopMoviesTab.forYou,
  };
}

class _DesktopMoviesPageState extends ConsumerState<DesktopMoviesPage> {
  late DesktopMoviesTab _tab = widget.initialTab;
  _MoviesSort _sort = _MoviesSort.recent;
  final ScrollController _scroll = ScrollController();
  final GlobalKey<MediaImportButtonState> _mediaImportKey =
      GlobalKey<MediaImportButtonState>();
  bool _matchMetadataAfterImport = true;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(DesktopMoviesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab) {
      _tab = widget.initialTab;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.jumpTo(0);
        }
      });
    }
  }

  void _openTab(DesktopMoviesTab tab) {
    setState(() => _tab = tab);
    if (_scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: DesktopMotion.fade,
        curve: DesktopMotion.ease,
      );
    }
  }

  List<MovieVideoItem> _sorted(List<MovieVideoItem> items) {
    final copy = [...items];
    switch (_sort) {
      case _MoviesSort.recent:
        copy.sort((a, b) => _updatedAt(b).compareTo(_updatedAt(a)));
      case _MoviesSort.rating:
        copy.sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));
      case _MoviesSort.year:
        copy.sort(
          (a, b) =>
              (b.releaseDate?.year ?? 0).compareTo(a.releaseDate?.year ?? 0),
        );
    }
    return copy;
  }

  List<MovieSeries> _sortedSeries(List<MovieSeries> items) {
    final copy = [...items];
    switch (_sort) {
      case _MoviesSort.recent:
        copy.sort(
          (a, b) => (b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
        );
      case _MoviesSort.rating:
        copy.sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));
      case _MoviesSort.year:
        copy.sort(
          (a, b) =>
              (b.firstAirDate?.year ?? 0).compareTo(a.firstAirDate?.year ?? 0),
        );
    }
    return copy;
  }

  bool _isEmptyTab({
    required List<MovieVideoItem> movies,
    required List<MovieSeries> series,
    required List<MovieSeries> anime,
    required List<MovieVideoItem> favorites,
    required List<MovieWatchHistory> history,
    required List<MovieContinueWatching> continueWatching,
    required List<MovieVideoItem> watchlistItems,
  }) {
    return switch (_tab) {
      DesktopMoviesTab.forYou =>
        movies.isEmpty &&
            series.isEmpty &&
            anime.isEmpty &&
            continueWatching.isEmpty,
      DesktopMoviesTab.continueWatching => continueWatching.isEmpty,
      DesktopMoviesTab.movies => movies.isEmpty,
      DesktopMoviesTab.series => series.isEmpty,
      DesktopMoviesTab.anime => anime.isEmpty,
      DesktopMoviesTab.favorites => favorites.isEmpty,
      DesktopMoviesTab.watchlist => watchlistItems.isEmpty,
      DesktopMoviesTab.history => history.isEmpty,
    };
  }

  Widget _importAction(BuildContext context, AppLocalizations l10n) {
    final appContainer = ProviderScope.containerOf(context, listen: false);
    bool isCurrentSession(int epoch) =>
        appContainer.read(sessionEpochProvider) == epoch;

    Future<void> refresh({int? sessionEpoch}) async {
      if (sessionEpoch != null && !isCurrentSession(sessionEpoch)) return;
      await appContainer.read(movieCenterControllerProvider.notifier).refresh();
      if (sessionEpoch != null && !isCurrentSession(sessionEpoch)) return;
      appContainer.invalidate(movieDashboardProvider);
    }

    Future<void> completeImport(
      MediaImportBatchResult result, {
      required bool matchMetadata,
      required int sessionEpoch,
    }) async {
      if (result.imported.isEmpty || !isCurrentSession(sessionEpoch)) return;
      final taskWaiter = appContainer.read(mediaImportTaskWaiterProvider);
      for (final file in result.imported) {
        if (!isCurrentSession(sessionEpoch)) return;
        final taskId = file.mediaAutoImportTaskId;
        if (taskId == null || taskId.isEmpty) continue;
        try {
          await taskWaiter.waitForTerminal(taskId);
        } on Object catch (error) {
          if (isCurrentSession(sessionEpoch) && mounted && context.mounted) {
            showDesktopToast(
              context,
              failureToast(l10n, l10n.videoAutoImportStatusUnknown, error),
              kind: DesktopToastKind.warn,
            );
          }
        }
        if (!isCurrentSession(sessionEpoch)) return;
        if (matchMetadata) {
          try {
            await appContainer
                .read(movieCenterControllerProvider.notifier)
                .createScrapeTaskForFileNodeId(file.fileNodeId);
          } on Object catch (error) {
            if (isCurrentSession(sessionEpoch) && mounted && context.mounted) {
              showDesktopToast(
                context,
                failureToast(l10n, l10n.desktopMoviesMatchMetadata, error),
                kind: DesktopToastKind.warn,
              );
            }
          }
        }
      }
      await refresh(sessionEpoch: sessionEpoch);
    }

    return MediaImportButton(
      key: _mediaImportKey,
      subsystemDirectory: 'Media',
      allowSharedSpace: true,
      acceptedExtensions: importExtensionsFor(DesktopImportModule.film),
      label: l10n.filesImport,
      onPressedOverride: () => unawaited(_openImportDialog(context, l10n)),
      buttonBuilder:
          (context, {required onPressed, required busy}) => DesktopButton(
            label: l10n.filesImport,
            icon: DesktopIcons.download,
            variant: DesktopButtonVariant.soft,
            onPressed: onPressed,
            busy: busy,
          ),
      onFilesPicked: (files, spaceType) {
        final matchMetadata = _matchMetadataAfterImport;
        final importSessionEpoch = appContainer.read(sessionEpochProvider);
        ref
            .read(mediaImportQueueProvider.notifier)
            .enqueue(
              files: files,
              directoryName: 'Media',
              spaceType: spaceType,
              reuseExistingFiles: false,
              titleForFile:
                  (file) =>
                      '${l10n.desktopMediaImportTaskMovies} · ${file.name}',
              onComplete: (result) async {
                await completeImport(
                  result,
                  matchMetadata: matchMetadata,
                  sessionEpoch: importSessionEpoch,
                );
                if (!isCurrentSession(importSessionEpoch) ||
                    !mounted ||
                    !context.mounted) {
                  return;
                }
                if (result.failures.isEmpty) {
                  showDesktopToast(
                    context,
                    l10n.importComplete(result.imported.length),
                    icon: DesktopIcons.check,
                  );
                } else {
                  showDesktopToast(
                    context,
                    l10n.importFailed,
                    kind: DesktopToastKind.warn,
                  );
                }
              },
            );
        showDesktopToast(
          context,
          l10n.desktopMediaImportQueued(files.length),
          icon: DesktopIcons.download,
          actionLabel: l10n.desktopViewTasks,
          onAction:
              () => appContainer
                  .read(desktopShellProvider.notifier)
                  .setPanel(DesktopPanel.tasks),
        );
      },
      onImportComplete: refresh,
      onImportCompleteWithResult: (result) async {
        await completeImport(
          result,
          matchMetadata: _matchMetadataAfterImport,
          sessionEpoch: appContainer.read(sessionEpochProvider),
        );
        return null;
      },
    );
  }

  Future<void> _openImportDialog(
    BuildContext context,
    AppLocalizations l10n,
  ) async {
    final selection = await showDesktopMediaImportDialog(
      context,
      kind: DesktopMediaImportKind.movies,
      allowSharedSpace: true,
    );
    if (!mounted || !context.mounted || selection == null) return;
    _matchMetadataAfterImport = selection.matchMetadata;
    if (selection.deviceFiles.isNotEmpty) {
      await _mediaImportKey.currentState?.importFiles(
        selection.deviceFiles,
        spaceType: selection.spaceType,
      );
      return;
    }
    if (selection.fileNodeIds.isNotEmpty) {
      await _importExistingFiles(context, l10n, selection);
    }
  }

  Future<void> _importExistingFiles(
    BuildContext context,
    AppLocalizations l10n,
    DesktopMediaImportSelection selection,
  ) async {
    try {
      final tasks = await ref
          .read(fileBrowserControllerProvider.notifier)
          .requestMediaImports(
            fileNodeIds: selection.fileNodeIds,
            mediaType: 'VIDEO',
          );
      if (!mounted || !context.mounted) return;
      showDesktopToast(
        context,
        l10n.importProcessing(tasks.length),
        kind: DesktopToastKind.info,
      );
      final taskWaiter = ref.read(mediaImportTaskWaiterProvider);
      for (final task in tasks) {
        try {
          await taskWaiter.waitForTerminal(task.taskId);
        } on Object catch (error) {
          if (!mounted || !context.mounted) return;
          showDesktopToast(
            context,
            failureToast(l10n, l10n.videoAutoImportStatusUnknown, error),
            kind: DesktopToastKind.warn,
          );
          continue;
        }
        if (!mounted || !context.mounted) return;
        if (selection.matchMetadata) {
          try {
            await ref
                .read(movieCenterControllerProvider.notifier)
                .createScrapeTaskForFileNodeId(task.fileNodeId);
          } on Object catch (error) {
            if (!mounted || !context.mounted) return;
            showDesktopToast(
              context,
              failureToast(l10n, l10n.desktopMoviesMatchMetadata, error),
              kind: DesktopToastKind.warn,
            );
          }
        }
      }
      if (!mounted || !context.mounted) return;
      await ref.read(movieCenterControllerProvider.notifier).refresh();
      if (!mounted || !context.mounted) return;
      ref.invalidate(movieDashboardProvider);
    } on Object catch (error) {
      if (!mounted || !context.mounted) return;
      showDesktopToast(
        context,
        failureToast(l10n, l10n.filesImport, error),
        kind: DesktopToastKind.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dashboardState = ref.watch(movieDashboardProvider);
    final dashboard = dashboardState.asData?.value;
    final recentMovies = dashboard?.recentlyAdded ?? const <MovieVideoItem>[];
    final continueWatching =
        dashboard?.continueWatching ?? const <MovieContinueWatching>[];
    final series = dashboard?.series ?? const <MovieSeries>[];
    final centerState = ref.watch(movieCenterControllerProvider);
    final center = centerState.asData?.value;
    final movies =
        center != null && center.movies.isNotEmpty
            ? center.movies
            : recentMovies;
    final favorites = center?.favoriteItems ?? const <MovieVideoItem>[];
    final history = center?.watchHistory ?? const <MovieWatchHistory>[];
    final anime = center?.animeSeries ?? const <MovieSeries>[];
    final watchlistItems = ref.watch(movieWatchlistProvider);
    final featured =
        recentMovies.where((item) => item.backdropUrl != null).take(3).toList();
    final heroItems = featured.isEmpty ? movies.take(3).toList() : featured;
    final initialLoading =
        (dashboard == null && dashboardState.isLoading) ||
        (center == null && centerState.isLoading);
    final activeTabCount = switch (_tab) {
      DesktopMoviesTab.continueWatching => continueWatching.length,
      DesktopMoviesTab.movies => movies.length,
      DesktopMoviesTab.series => series.length,
      DesktopMoviesTab.anime => anime.length,
      DesktopMoviesTab.favorites => favorites.length,
      DesktopMoviesTab.watchlist => watchlistItems.length,
      DesktopMoviesTab.history => history.length,
      DesktopMoviesTab.forYou => movies.length,
    };
    final activeTabTitle = switch (_tab) {
      DesktopMoviesTab.continueWatching => l10n.desktopContinueWatching,
      DesktopMoviesTab.movies => l10n.desktopMoviesFeatureFilms,
      DesktopMoviesTab.series => l10n.videoSectionSeries,
      DesktopMoviesTab.anime => l10n.videoSectionAnime,
      DesktopMoviesTab.favorites => l10n.photosTabFavorites,
      DesktopMoviesTab.watchlist => l10n.desktopWatchlist,
      DesktopMoviesTab.history => l10n.desktopHistory,
      DesktopMoviesTab.forYou => l10n.desktopForYou,
    };

    return DesktopSliverPage(
      controller: _scroll,
      topPadding: DesktopMetrics.pageTopPaddingCompact,
      slivers: [
        SliverToBoxAdapter(
          child:
              heroItems.isNotEmpty
                  ? _Cinema(
                    items: heroItems,
                    continueWatching: continueWatching,
                  )
                  : initialLoading
                  ? const _CinemaSkeleton()
                  : const _CinemaPlaceholder(),
        ),
        DesktopStickySliver(
          child: _Head(
            tab: _tab,
            onChanged: _openTab,
            importAction: _importAction(context, l10n),
            // 占位符顺序为 {titleCount} titles · {continueCount} in progress，
            // v16 补齐 @placeholders 后参数顺序以文案为准，不能沿用旧顺序。
            subtitle: l10n.moviesModuleSubtitle(
              dashboard?.stats.movieCount ?? movies.length,
              continueWatching.length,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SortRow(sort: _sort, onSort: (v) => setState(() => _sort = v)),
              if (initialLoading)
                _MoviesLoadingTracks(tab: _tab)
              else if (_tab == DesktopMoviesTab.forYou) ...[
                if (continueWatching.isNotEmpty)
                  DesktopSection(
                    eyebrow: l10n.desktopPickUpWhereYouLeft,
                    title: l10n.desktopContinueWatching,
                    actionLabel: l10n.desktopSeeAll,
                    onAction: () => _openTab(DesktopMoviesTab.history),
                    child: _WideRail(items: continueWatching),
                  ),
                if (movies.isNotEmpty)
                  DesktopSection(
                    eyebrow: l10n.desktopMoviesTitlesCount(movies.length),
                    title: l10n.desktopMoviesFeatureFilms,
                    actionLabel: l10n.desktopSeeAllCount(movies.length),
                    onAction: () => _openTab(DesktopMoviesTab.movies),
                    child: _PosterRail(
                      items: _sorted(movies).take(10).toList(),
                    ),
                  ),
                if (series.isNotEmpty)
                  DesktopSection(
                    eyebrow: l10n.desktopMoviesTitlesCount(series.length),
                    title: l10n.videoSectionSeries,
                    actionLabel: l10n.desktopSeeAllCount(series.length),
                    onAction: () => _openTab(DesktopMoviesTab.series),
                    child: _SeriesRail(
                      items: _sortedSeries(series).take(10).toList(),
                    ),
                  ),
                if (anime.isNotEmpty)
                  DesktopSection(
                    eyebrow: l10n.desktopMoviesTitlesCount(anime.length),
                    title: l10n.videoSectionAnime,
                    actionLabel: l10n.desktopSeeAllCount(anime.length),
                    onAction: () => _openTab(DesktopMoviesTab.anime),
                    child: _SeriesRail(
                      items: _sortedSeries(anime).take(10).toList(),
                    ),
                  ),
              ] else ...[
                if (_tab == DesktopMoviesTab.movies ||
                    _tab == DesktopMoviesTab.series ||
                    _tab == DesktopMoviesTab.anime)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: DesktopLink(
                        label: l10n.desktopForYou,
                        icon: DesktopIcons.left,
                        trailing: false,
                        onPressed: () => _openTab(DesktopMoviesTab.forYou),
                      ),
                    ),
                  ),
                if (_tab == DesktopMoviesTab.continueWatching ||
                    _tab == DesktopMoviesTab.history)
                  DesktopSection(
                    eyebrow: l10n.desktopMoviesTitlesCount(activeTabCount),
                    title: activeTabTitle,
                    child:
                        _tab == DesktopMoviesTab.continueWatching
                            ? _WideGrid(items: continueWatching)
                            : _HistoryGrid(
                              entries: history,
                              onClear: () async {
                                final snapshot = List<MovieWatchHistory>.of(
                                  history,
                                );
                                try {
                                  await ref
                                      .read(
                                        movieCenterControllerProvider.notifier,
                                      )
                                      .clearHistory();
                                  if (!context.mounted) {
                                    return;
                                  }
                                  showDesktopToast(
                                    context,
                                    l10n.videoClearHistory,
                                    kind: DesktopToastKind.success,
                                    actionLabel: l10n.desktopUndo,
                                    onAction:
                                        () => unawaited(
                                          _restoreHistory(snapshot),
                                        ),
                                  );
                                } on Exception catch (error) {
                                  if (!context.mounted) {
                                    return;
                                  }
                                  showDesktopToast(
                                    context,
                                    userFacingErrorText(error),
                                    kind: DesktopToastKind.error,
                                  );
                                }
                              },
                            ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DesktopEyebrow(
                          l10n.desktopMoviesTitlesCount(activeTabCount),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            activeTabTitle,
                            style: DesktopType.sectionTitle(
                              DesktopSkin.of(context).text,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
        if (!initialLoading && _tab == DesktopMoviesTab.movies)
          _PosterSliverGrid(items: _sorted(movies)),
        if (!initialLoading && _tab == DesktopMoviesTab.favorites)
          _PosterSliverGrid(items: _sorted(favorites)),
        if (!initialLoading && _tab == DesktopMoviesTab.watchlist)
          _PosterSliverGrid(items: _sorted(watchlistItems)),
        if (!initialLoading && _tab == DesktopMoviesTab.series)
          _SeriesSliverGrid(items: _sortedSeries(series)),
        if (!initialLoading && _tab == DesktopMoviesTab.anime)
          _SeriesSliverGrid(items: _sortedSeries(anime)),
        if (!initialLoading &&
            !dashboardState.isLoading &&
            !centerState.isLoading &&
            _isEmptyTab(
              movies: movies,
              series: series,
              anime: anime,
              favorites: favorites,
              history: history,
              continueWatching: continueWatching,
              watchlistItems: watchlistItems,
            ))
          SliverToBoxAdapter(child: _MoviesEmpty(tab: _tab)),
      ],
    );
  }

  Future<void> _restoreHistory(List<MovieWatchHistory> snapshot) async {
    final l10n = AppLocalizations.of(context);
    try {
      await ref
          .read(movieCenterControllerProvider.notifier)
          .restoreHistory(snapshot);
      if (!mounted) return;
      showDesktopToast(
        context,
        l10n.videoHistoryRestored,
        icon: DesktopIcons.undo,
        kind: DesktopToastKind.success,
      );
    } on Exception catch (error) {
      if (!mounted) return;
      showDesktopToast(
        context,
        userFacingErrorText(error),
        icon: DesktopIcons.info,
        kind: DesktopToastKind.error,
      );
    }
  }
}

/// 分档空态（样例 `Movies.tsx:83` 的 `Empty size="lg"`）。
class _MoviesEmpty extends StatelessWidget {
  const _MoviesEmpty({required this.tab});

  final DesktopMoviesTab tab;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final l10nIcons = switch (tab) {
      DesktopMoviesTab.favorites => DesktopIcons.heart,
      DesktopMoviesTab.watchlist => DesktopIcons.plus,
      DesktopMoviesTab.history ||
      DesktopMoviesTab.continueWatching => DesktopIcons.history,
      DesktopMoviesTab.anime => DesktopIcons.sparkle,
      _ => DesktopIcons.film,
    };
    final title = switch (tab) {
      DesktopMoviesTab.favorites => l10n.desktopMoviesEmptyFavoritesTitle,
      DesktopMoviesTab.watchlist => l10n.desktopMoviesEmptyWatchlistTitle,
      DesktopMoviesTab.series => l10n.desktopMoviesEmptySeriesTitle,
      DesktopMoviesTab.anime => l10n.desktopMoviesEmptyAnimeTitle,
      DesktopMoviesTab.history ||
      DesktopMoviesTab.continueWatching => l10n.desktopMoviesEmptyHistoryTitle,
      _ => l10n.libraryNoMovies,
    };
    final body = switch (tab) {
      DesktopMoviesTab.favorites => l10n.desktopMoviesEmptyFavoritesBody,
      DesktopMoviesTab.watchlist => l10n.desktopMoviesEmptyWatchlistBody,
      DesktopMoviesTab.series => l10n.desktopMoviesEmptySeriesBody,
      DesktopMoviesTab.anime => l10n.desktopMoviesEmptyAnimeBody,
      DesktopMoviesTab.history ||
      DesktopMoviesTab.continueWatching => l10n.desktopMoviesEmptyHistoryBody,
      _ => l10n.desktopMoviesEmptyLibraryBody,
    };
    return DesktopEmpty(
      icon: l10nIcons,
      message: title,
      description: body,
      large: true,
    );
  }
}

enum _MoviesSort { recent, rating, year }

class _Head extends StatelessWidget {
  const _Head({
    required this.tab,
    required this.onChanged,
    required this.importAction,
    required this.subtitle,
  });

  final DesktopMoviesTab tab;
  final ValueChanged<DesktopMoviesTab> onChanged;
  final Widget importAction;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DesktopPageHead(
      eyebrow: subtitle.toUpperCase(),
      title: l10n.moduleMoviesTitle,
      sticky: true,
      actionsRightAlignedWhenWrapped: true,
      actions: [
        importAction,
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DesktopSeg<DesktopMoviesTab>(
            options: desktopMoviesSegTabs,
            value: tab,
            labelOf:
                (value) => switch (value) {
                  DesktopMoviesTab.forYou => l10n.desktopForYou,
                  DesktopMoviesTab.movies => l10n.videoSectionFilms,
                  DesktopMoviesTab.series => l10n.videoSectionSeries,
                  DesktopMoviesTab.anime => l10n.videoSectionAnime,
                  DesktopMoviesTab.favorites => l10n.photosTabFavorites,
                  DesktopMoviesTab.watchlist => l10n.desktopWatchlist,
                  DesktopMoviesTab.history => l10n.desktopHistory,
                  DesktopMoviesTab.continueWatching => l10n.desktopForYou,
                },
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _SortRow extends StatelessWidget {
  const _SortRow({required this.sort, required this.onSort});

  final _MoviesSort sort;
  final ValueChanged<_MoviesSort> onSort;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final labels = <_MoviesSort, String>{
      _MoviesSort.recent: l10n.desktopSortRecent,
      _MoviesSort.rating: l10n.desktopSortRating,
      _MoviesSort.year: l10n.desktopSortYear,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        children: [
          Icon(DesktopIcons.sort, size: 15, color: skin.text3),
          const SizedBox(width: 6),
          for (final value in _MoviesSort.values) ...[
            DesktopChipButton(
              label: labels[value] ?? '',
              selected: sort == value,
              onTap: () => onSort(value),
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}
