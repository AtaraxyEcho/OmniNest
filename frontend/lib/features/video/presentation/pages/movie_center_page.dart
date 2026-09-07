import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/widgets/app_error_view.dart';
import 'package:omninest/core/widgets/app_loading.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/domain/movie_library_models.dart';
import 'package:omninest/features/video/presentation/theme/movie_redesign_theme.dart';
import 'package:omninest/features/video/presentation/widgets/movie_collections.dart';
import 'package:omninest/features/video/presentation/widgets/movie_history.dart';
import 'package:omninest/features/video/presentation/widgets/movie_management.dart';
import 'package:omninest/features/video/presentation/widgets/movie_shell.dart';
import 'package:omninest/features/video/presentation/widgets/redesign/movie_redesign_continue.dart';
import 'package:omninest/features/video/presentation/widgets/redesign/movie_redesign_empty_state.dart';
import 'package:omninest/features/video/presentation/widgets/redesign/movie_redesign_filter_sort_bar.dart';
import 'package:omninest/features/video/presentation/widgets/redesign/movie_redesign_poster_card.dart';
import 'package:omninest/features/video/presentation/widgets/redesign/movie_redesign_section_header.dart';
import 'package:omninest/features/video/presentation/widgets/redesign/movie_redesign_time.dart';

class MovieCenterPage extends ConsumerWidget {
  const MovieCenterPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(movieCenterControllerProvider);
    return state.when(
      data: (data) {
        // 管理分区不再静默回退到电影：无权限时由内容区显示明确提示，
        // 避免用户点击「媒体库管理」等管理项后被悄悄带回电影页。
        final visibleState = data;
        return Column(
          children: [
            if (data.errorMessage != null)
              MaterialBanner(
                content: Text(data.errorMessage!),
                backgroundColor: Theme.of(context).colorScheme.errorContainer,
                actions: [
                  TextButton(
                    onPressed:
                        () =>
                            ref
                                .read(movieCenterControllerProvider.notifier)
                                .clearError(),
                    child: Text(AppLocalizations.of(context).videoClose),
                  ),
                ],
              ),
            Expanded(
              child: MovieShell(
                section: visibleState.section,
                childOwnsScroll: true,
                onSectionSelected:
                    ref
                        .read(movieCenterControllerProvider.notifier)
                        .selectSection,
                counts: {
                  MovieSection.movies: visibleState.dashboard.stats.movieCount,
                  MovieSection.tvShows:
                      visibleState.dashboard.stats.seriesCount,
                  MovieSection.anime: visibleState.animeSeries.length,
                  MovieSection.collections: visibleState.collections.length,
                  MovieSection.continueWatching:
                      visibleState.continueWatching.length,
                  MovieSection.favorites: visibleState.favoriteItems.length,
                  MovieSection.history: visibleState.watchHistory.length,
                },
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(child: _MovieSearchField(state: visibleState)),
                  ],
                ),
                onRefresh: () async {
                  await ref
                      .read(movieCenterControllerProvider.notifier)
                      .refresh();
                },
                child: _MovieContent(state: visibleState),
              ),
            ),
          ],
        );
      },
      error:
          (error, stackTrace) => Scaffold(
            backgroundColor: context.movieRedesign.background,
            body: AppErrorView(
              message: describeUserFacingError(error).displayMessage,
              onRetry: () => ref.invalidate(movieCenterControllerProvider),
            ),
          ),
      loading:
          () => Scaffold(
            backgroundColor: context.movieRedesign.background,
            body: AppLoading.grid(gridAspectRatio: 0.62),
          ),
    );
  }
}

class _MovieSearchField extends ConsumerWidget {
  const _MovieSearchField({required this.state});

  final MovieCenterState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.movieRedesign;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: TextField(
        onChanged:
            ref.read(movieCenterControllerProvider.notifier).setSearchQuery,
        style: TextStyle(
          fontFamily: 'JetBrainsMono',
          fontFamilyFallback: const ['NotoSansSC'],
          color: palette.foreground,
          fontSize: 13,
          height: 18 / 13,
        ),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: palette.muted,
          hintText: AppLocalizations.of(context).videoRedesignSearchHint(
            state.section.labelOf(AppLocalizations.of(context)),
          ),
          hintStyle: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontFamilyFallback: const ['NotoSansSC'],
            color: palette.mutedForeground,
            fontSize: 13,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: palette.mutedForeground,
            size: 16,
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 34),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 8,
          ),
          border: OutlineInputBorder(
            borderRadius: MovieRedesignPalette.borderRadius,
            borderSide: BorderSide(color: palette.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: MovieRedesignPalette.borderRadius,
            borderSide: BorderSide(color: palette.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: MovieRedesignPalette.borderRadius,
            borderSide: BorderSide(color: palette.foreground),
          ),
        ),
      ),
    );
  }
}

class _MovieContent extends ConsumerWidget {
  const _MovieContent({required this.state});

  final MovieCenterState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final user = ref.watch(authSessionProvider).asData?.value.user;
    final canManage =
        user?.permissions.contains('media:library:manage') ?? false;
    if (state.section.requiresManagementRole && !canManage) {
      return _ManagementAccessDenied(l10n: l10n);
    }
    if (state.loadingSections.contains(state.section) &&
        !state.loadedSections.contains(state.section)) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: AppLoading.grid(gridAspectRatio: 0.62),
      );
    }
    return switch (state.section) {
      MovieSection.movies => _MovieLibrarySection(state: state),
      MovieSection.tvShows => _SeriesGridSection(
        title: l10n.videoSectionTvShows,
        subtitleEn: l10n.videoRedesignSubTvShows,
        subtitle: l10n.videoSeriesLibrarySubtitle,
        series: state.filteredSeries,
      ),
      MovieSection.anime => _SeriesGridSection(
        title: l10n.videoSectionAnime,
        subtitleEn: l10n.videoRedesignSubAnime,
        subtitle: l10n.videoAnimeLibrarySubtitle,
        series: state.filteredAnimeSeries,
      ),
      MovieSection.collections => CollectionsSection(
        totalCount: state.movies.length,
        collections: state.collections,
      ),
      MovieSection.recent => _RecentSection(state: state),
      MovieSection.continueWatching => _ContinueSection(state: state),
      MovieSection.favorites => _FavoritesSection(state: state),
      MovieSection.history => HistorySection(
        items: state.watchHistory,
        onDelete:
            (entry) => ref
                .read(movieCenterControllerProvider.notifier)
                .deleteHistoryItem(entry),
        onClearAll:
            () =>
                ref.read(movieCenterControllerProvider.notifier).clearHistory(),
      ),
      MovieSection.management => const MovieAdminSection(),
    };
  }
}

class _ManagementAccessDenied extends StatelessWidget {
  const _ManagementAccessDenied({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.admin_panel_settings_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              l10n.videoManageAdminOnly,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 电影卡片：点击进详情（批次 4 换详情抽屉），播放进播放器。
MovieRedesignCardData _movieCard(BuildContext context, MovieVideoItem item) {
  return MovieRedesignCardData.fromVideoItem(item).copyWith(
    onTap: () => _openDetail(context, item),
    onPlay: () {
      unawaited(context.push('/video/${item.id}/play'));
    },
  );
}

void _openDetail(BuildContext context, MovieVideoItem item) {
  if (item.mediaType == 'TV') {
    context.push('/video/series/${item.id}');
  } else {
    context.push('/video/${item.id}');
  }
}

/// 电影分区：标题 + 继续观看横条 + 状态筛选/排序 + 海报分页网格。
class _MovieLibrarySection extends ConsumerStatefulWidget {
  const _MovieLibrarySection({required this.state});

  final MovieCenterState state;

  @override
  ConsumerState<_MovieLibrarySection> createState() =>
      _MovieLibrarySectionState();
}

class _MovieLibrarySectionState extends ConsumerState<_MovieLibrarySection> {
  final ScrollController _scrollController = ScrollController();
  bool _requestingNextPage = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _requestingNextPage) {
      return;
    }
    final position = _scrollController.position;
    if (position.maxScrollExtent - position.pixels > 720) {
      return;
    }
    final state = widget.state;
    if (state.section != MovieSection.movies ||
        !state.movieHasMore ||
        state.movieLoadingMore) {
      return;
    }
    _requestingNextPage = true;
    unawaited(_loadNextPage());
  }

  Future<void> _loadNextPage() async {
    try {
      await ref
          .read(movieCenterControllerProvider.notifier)
          .loadNextLibraryPage();
    } finally {
      _requestingNextPage = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(movieCenterControllerProvider.notifier);
    final filteredItems = state.filteredMovies;
    final continueItems = [
      for (final item in state.continueWatching)
        MovieRedesignContinueItem(
          data: item,
          timeText: movieRedesignRelativeTime(context, item.updatedAt),
          onPlay: () => unawaited(context.push('/video/${item.id}/play')),
        ),
    ];
    final filters = [
      MovieRedesignChip(value: 'all', label: l10n.videoRedesignFilterAll),
      MovieRedesignChip(
        value: 'matched',
        label: l10n.videoRedesignFilterMatched,
      ),
      MovieRedesignChip(
        value: 'pending',
        label: l10n.videoRedesignFilterPending,
      ),
      MovieRedesignChip(value: 'failed', label: l10n.videoRedesignFilterFailed),
    ];
    final sorts = [
      MovieRedesignChip(value: 'dateAdded', label: l10n.videoSortDateAdded),
      MovieRedesignChip(value: 'rating', label: l10n.videoRating),
      MovieRedesignChip(value: 'releaseDate', label: l10n.videoYear),
      MovieRedesignChip(value: 'title', label: l10n.videoSortTitle),
    ];
    return CustomScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
          sliver: SliverToBoxAdapter(
            child: MovieRedesignSectionHeader(
              title: l10n.videoMovieLibrary,
              subtitleEn: l10n.videoRedesignSubMovies,
              count: filteredItems.isEmpty ? null : filteredItems.length,
              subtitle: l10n.videoMovieLibrarySubtitle,
            ),
          ),
        ),
        if (continueItems.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            sliver: SliverToBoxAdapter(
              child: MovieRedesignContinueStrip(
                title: l10n.videoSectionContinueWatching,
                subtitleEn: l10n.videoRedesignSubContinue,
                items: continueItems,
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
          sliver: SliverToBoxAdapter(
            child: MovieRedesignFilterSortBar(
              filters: filters,
              filterValue: state.filter.name,
              onFilter: (value) {
                controller.setFilter(
                  MovieLibraryFilter.values.firstWhere((f) => f.name == value),
                );
              },
              sorts: sorts,
              sortValue: state.sortBy.name,
              onSort: (value) {
                controller.setSort(
                  MovieSortBy.values.firstWhere((s) => s.name == value),
                );
              },
            ),
          ),
        ),
        if (filteredItems.isEmpty)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            sliver: SliverToBoxAdapter(
              child: MovieRedesignEmptyState(
                icon: Icons.movie_outlined,
                title: l10n.videoRedesignNoMatches,
                subtitle: l10n.videoRedesignAdjustFilters,
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            sliver: MovieRedesignPosterSliverGrid(
              items: [
                for (final item in filteredItems) _movieCard(context, item),
              ],
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(4, 24, 4, 48),
          sliver: SliverToBoxAdapter(
            child: Center(
              child:
                  state.movieLoadingMore
                      ? const SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    );
  }
}

/// 剧集/动漫分区：系列海报网格，点击进剧集详情。
class _SeriesGridSection extends StatelessWidget {
  const _SeriesGridSection({
    required this.title,
    required this.subtitleEn,
    required this.subtitle,
    required this.series,
  });

  final String title;
  final String subtitleEn;
  final String subtitle;
  final List<MovieSeries> series;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
          sliver: SliverToBoxAdapter(
            child: MovieRedesignSectionHeader(
              title: title,
              subtitleEn: subtitleEn,
              count: series.isEmpty ? null : series.length,
              subtitle: subtitle,
            ),
          ),
        ),
        if (series.isEmpty)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            sliver: SliverToBoxAdapter(
              child: MovieRedesignEmptyState(
                icon: Icons.tv_outlined,
                title: l10n.videoNoMediaItems,
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            sliver: MovieRedesignPosterSliverGrid(
              items: [
                for (final item in series)
                  MovieRedesignCardData.fromSeries(item).copyWith(
                    onTap: () => context.push('/video/series/${item.id}'),
                  ),
              ],
            ),
          ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 48)),
      ],
    );
  }
}

/// 最近添加分区。
class _RecentSection extends StatelessWidget {
  const _RecentSection({required this.state});

  final MovieCenterState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
          sliver: SliverToBoxAdapter(
            child: MovieRedesignSectionHeader(
              title: l10n.videoSectionRecent,
              subtitleEn: l10n.videoRedesignSubRecent,
              count:
                  state.recentItems.isEmpty ? null : state.recentItems.length,
              subtitle: l10n.videoRecentSubtitle,
            ),
          ),
        ),
        if (state.recentItems.isEmpty)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            sliver: SliverToBoxAdapter(
              child: MovieRedesignEmptyState(
                icon: Icons.new_releases_outlined,
                title: l10n.videoNoMediaItems,
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            sliver: MovieRedesignPosterSliverGrid(
              items: [
                for (final item in state.recentItems) _movieCard(context, item),
              ],
            ),
          ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 48)),
      ],
    );
  }
}

/// 继续观看分区：2/4 列进度卡片。
class _ContinueSection extends StatelessWidget {
  const _ContinueSection({required this.state});

  final MovieCenterState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
          sliver: SliverToBoxAdapter(
            child: MovieRedesignSectionHeader(
              title: l10n.videoSectionContinueWatching,
              subtitleEn: l10n.videoRedesignSubContinue,
              count:
                  state.continueWatching.isEmpty
                      ? null
                      : state.continueWatching.length,
            ),
          ),
        ),
        if (state.continueWatching.isEmpty)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            sliver: SliverToBoxAdapter(
              child: MovieRedesignEmptyState(
                icon: Icons.play_circle_outline_rounded,
                title: l10n.videoNoMediaItems,
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            sliver: SliverToBoxAdapter(
              child: _ContinueCardWrap(
                items: [
                  for (final item in state.continueWatching)
                    MovieRedesignContinueItem(
                      data: item,
                      timeText: movieRedesignRelativeTime(
                        context,
                        item.updatedAt,
                      ),
                      onPlay:
                          () =>
                              unawaited(context.push('/video/${item.id}/play')),
                    ),
                ],
              ),
            ),
          ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 48)),
      ],
    );
  }
}

class _ContinueCardWrap extends StatelessWidget {
  const _ContinueCardWrap({required this.items});

  final List<MovieRedesignContinueItem> items;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 1024 ? 4 : (width >= 640 ? 2 : 1);
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = 12.0;
        final cardWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final item in items)
              SizedBox(
                width: cardWidth,
                child: MovieRedesignContinueCard(item: item),
              ),
          ],
        );
      },
    );
  }
}

/// 收藏分区。
class _FavoritesSection extends StatelessWidget {
  const _FavoritesSection({required this.state});

  final MovieCenterState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
          sliver: SliverToBoxAdapter(
            child: MovieRedesignSectionHeader(
              title: l10n.videoSectionFavorites,
              subtitleEn: l10n.videoRedesignSubFavorites,
              count:
                  state.favoriteItems.isEmpty
                      ? null
                      : state.favoriteItems.length,
              subtitle: l10n.videoFavoritesSubtitle,
            ),
          ),
        ),
        if (state.favoriteItems.isEmpty)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            sliver: SliverToBoxAdapter(
              child: MovieRedesignEmptyState(
                icon: Icons.favorite_rounded,
                title: l10n.videoRedesignNoFavorites,
                subtitle: l10n.videoRedesignNoFavoritesHint,
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            sliver: MovieRedesignPosterSliverGrid(
              items: [
                for (final item in state.favoriteItems)
                  _movieCard(context, item),
              ],
            ),
          ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 48)),
      ],
    );
  }
}
