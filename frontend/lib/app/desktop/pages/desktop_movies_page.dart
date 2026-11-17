import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_router_scope.dart';
import 'package:omninest/app/desktop/desktop_routes.dart';
import 'package:omninest/app/desktop/desktop_toast.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_cover.dart';
import 'package:omninest/app/desktop/widgets/desktop_surfaces.dart';
import 'package:omninest/app/desktop/widgets/desktop_tilt.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_palette.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/features/video/video_dashboard.dart';

// 一个页面三个部分：浏览骨架、影院轮播、海报与轨道。三块合起来超过
// 单文件 800 行的源码闸门，按职责拆成 part 而不是压行数。
part 'desktop_movies_cinema.dart';
part 'desktop_movies_cards.dart';

/// 桌面影视页（样例 `Movies.tsx` 的 `Browse`）。
///
/// 与模块内的移动页并行存在：壳层按形态分派到这一页，数据仍走同一批
/// provider。首页那套「影院轮播 + 分区轨道 + 倾斜海报」的结构在这里
/// 复用，避免影视模块又长出一套自己的排版语言。
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

  /// 当前页面确实没有可展示内容时显示空态，避免空库首屏留下大块空白。
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

    return Scrollbar(
      controller: _scroll,
      child: SingleChildScrollView(
        controller: _scroll,
        child: DesktopPage(
          topPadding: DesktopMetrics.pageTopPaddingCompact,
          children: [
            if (heroItems.isNotEmpty) _Cinema(items: heroItems),
            _Head(
              tab: _tab,
              onBack: () => _openTab(DesktopMoviesTab.forYou),
              // 生成方法的形参顺序是 (continueCount, titleCount)：ARB 里
              // 两个占位符都是 Object，排序与文案顺序不一致，别按字面传。
              subtitle: l10n.moviesModuleSubtitle(
                continueWatching.length,
                dashboard?.stats.movieCount ?? movies.length,
              ),
            ),
            _SortRow(sort: _sort, onSort: (v) => setState(() => _sort = v)),
            if (_tab == DesktopMoviesTab.forYou) ...[
              if (continueWatching.isNotEmpty)
                DesktopSection(
                  eyebrow: l10n.desktopPickUpWhereYouLeft,
                  title: l10n.desktopContinueWatching,
                  actionLabel: l10n.desktopHistory,
                  onAction: () => _openTab(DesktopMoviesTab.history),
                  child: _WideRail(items: continueWatching),
                ),
              if (movies.isNotEmpty)
                DesktopSection(
                  eyebrow: l10n.videoHostedFilmsEyebrow,
                  title: l10n.desktopAllMovies,
                  actionLabel: l10n.desktopAllMovies,
                  onAction: () => _openTab(DesktopMoviesTab.movies),
                  child: _PosterRail(items: _sorted(movies).take(10).toList()),
                ),
              if (series.isNotEmpty)
                DesktopSection(
                  eyebrow: l10n.desktopItemCount(series.length),
                  title: l10n.videoSectionSeries,
                  child: _SeriesRail(items: series.take(10).toList()),
                ),
              if (anime.isNotEmpty)
                DesktopSection(
                  eyebrow: l10n.desktopItemCount(anime.length),
                  title: l10n.videoSectionAnime,
                  actionLabel: l10n.videoSectionAnime,
                  onAction: () => _openTab(DesktopMoviesTab.anime),
                  child: _SeriesRail(items: anime.take(10).toList()),
                ),
            ] else if (_tab == DesktopMoviesTab.continueWatching)
              _WideGrid(items: continueWatching)
            else if (_tab == DesktopMoviesTab.movies)
              _PosterGrid(items: _sorted(movies))
            else if (_tab == DesktopMoviesTab.favorites)
              _PosterGrid(items: _sorted(favorites))
            else if (_tab == DesktopMoviesTab.watchlist)
              _PosterGrid(items: _sorted(watchlistItems))
            else if (_tab == DesktopMoviesTab.anime)
              _SeriesGrid(items: anime)
            else if (_tab == DesktopMoviesTab.history)
              _HistoryGrid(
                entries: history,
                onClear: () async {
                  final snapshot = List<MovieWatchHistory>.of(history);
                  try {
                    await ref
                        .read(movieCenterControllerProvider.notifier)
                        .clearHistory();
                    if (!context.mounted) {
                      return;
                    }
                    showDesktopToast(
                      context,
                      l10n.videoClearHistory,
                      kind: DesktopToastKind.success,
                      actionLabel: l10n.desktopUndo,
                      onAction: () => unawaited(_restoreHistory(snapshot)),
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
              )
            else
              _SeriesGrid(items: series),
            if (!dashboardState.isLoading &&
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
              _MoviesEmpty(tab: _tab),
          ],
        ),
      ),
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
///
/// 图标跟分档走：收藏是心形、历史是时钟、其余是胶片。文案也分档，
/// 「还没有收藏」和「片库为空」是两件事，不该共用一句话。
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
      DesktopMoviesTab.history ||
      DesktopMoviesTab.continueWatching => l10n.desktopMoviesEmptyHistoryTitle,
      _ => l10n.libraryNoMovies,
    };
    final body = switch (tab) {
      DesktopMoviesTab.favorites => l10n.desktopMoviesEmptyFavoritesBody,
      DesktopMoviesTab.watchlist => l10n.desktopMoviesEmptyWatchlistBody,
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
    required this.onBack,
    required this.subtitle,
  });

  final DesktopMoviesTab tab;
  final VoidCallback onBack;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DesktopPageHead(
      eyebrow: subtitle.toUpperCase(),
      title: l10n.moduleMoviesTitle,
      // 分类可由已有侧栏深链直达；主页面只保留原型的内容轨道，不增加七项
      // 顶部分段。分类列表使用单一返回动作回到内容首页。
      actions:
          tab == DesktopMoviesTab.forYou
              ? const []
              : [
                DesktopLink(
                  label: l10n.desktopForYou,
                  icon: DesktopIcons.left,
                  trailing: false,
                  onPressed: onBack,
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

/// 影院轮播（样例 `.cinema`）：7s 自动切换、悬停暂停、当前帧做 ken-burns
/// 缓推，文案按 100ms 递增入场。
