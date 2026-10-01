import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/widgets/infinite_scroll.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/auth/user_capabilities.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/widgets/app_error_view.dart';
import 'package:omninest/core/widgets/app_loading.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/domain/movie_detail_routes.dart';
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

class MovieCenterPage extends ConsumerStatefulWidget {
  const MovieCenterPage({super.key});

  @override
  ConsumerState<MovieCenterPage> createState() => _MovieCenterPageState();
}

class _MovieCenterPageState extends ConsumerState<MovieCenterPage> {
  // 进入页面的重进刷新节流：provider 常驻内存，posterUrl 是 2h/6h 的
  // 临时地址，不刷新则过期后海报灰块；15s 内往返不重复拉取。
  static DateTime? _lastEntryRefreshAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final now = DateTime.now();
      final last = _lastEntryRefreshAt;
      if (last != null && now.difference(last) < const Duration(seconds: 15)) {
        return;
      }
      _lastEntryRefreshAt = now;
      unawaited(ref.read(movieCenterControllerProvider.notifier).refresh());
    });
  }

  @override
  Widget build(BuildContext context) {
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
                  // 剧集/动漫各读独立系列列表：分区加载互不覆盖，
                  // 且与各自分区网格数据同源，避免计数被清零或漂移。
                  MovieSection.tvShows: visibleState.tvSeries.length,
                  MovieSection.anime: visibleState.animeSeries.length,
                  // 收藏/历史/合集/继续观看读服务端权威统计，
                  // 分区列表仍懒加载，徽标不受访问与否影响。
                  MovieSection.collections:
                      visibleState.dashboard.stats.collectionsCount,
                  MovieSection.continueWatching:
                      visibleState.dashboard.stats.continueWatchingCount,
                  MovieSection.favorites:
                      visibleState.dashboard.stats.favoritesCount,
                  MovieSection.history:
                      visibleState.dashboard.stats.historyCount,
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
          fontSize: AppTypography.bodyMedium,
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
            fontSize: AppTypography.bodyMedium,
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
    final canManage = ref.watch(userCapabilitiesProvider).canManageMediaLibrary;
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
        anime: false,
      ),
      MovieSection.anime => _SeriesGridSection(
        title: l10n.videoSectionAnime,
        subtitleEn: l10n.videoRedesignSubAnime,
        subtitle: l10n.videoAnimeLibrarySubtitle,
        series: state.filteredAnimeSeries,
        anime: true,
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
        hasMore: state.historyPaging.hasMore,
        isLoadingMore: state.historyPaging.isLoadingMore,
        onLoadMore:
            () =>
                ref
                    .read(movieCenterControllerProvider.notifier)
                    .loadMoreHistory(),
        // 无 activity:write 的角色隐藏删历史入口，只保留浏览。
        onDelete:
            ref.watch(userCapabilitiesProvider).canManageOwnActivity
                ? (entry) => ref
                    .read(movieCenterControllerProvider.notifier)
                    .deleteHistoryItem(entry)
                : null,
        onClearAll:
            ref.watch(userCapabilitiesProvider).canManageOwnActivity
                ? () =>
                    ref
                        .read(movieCenterControllerProvider.notifier)
                        .clearHistory()
                : null,
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
                fontSize: AppTypography.bodyLarge,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 电影卡片：点击打开页内详情抽屉，系列分集进剧集详情，播放进播放器。
MovieRedesignCardData _movieCard(
  BuildContext context,
  WidgetRef ref,
  MovieVideoItem item,
) {
  return MovieRedesignCardData.fromVideoItem(item).copyWith(
    onTap: () {
      // 分集持有 seriesId 时进剧集详情选集；电影进影片详情。
      // 不能用 mediaType=='TV'（后端仅有 MOVIE/EPISODE），也不能用分集 id 拼系列路由。
      context.push(movieDetailRoute(item));
    },
    onPlay: () {
      unawaited(context.push(moviePlayRoute(item.id)));
    },
  );
}

/// 系列卡片：悬停播放优先续播该系列，否则进系列详情；点击仍进详情。
MovieRedesignCardData _seriesCard(
  BuildContext context,
  MovieCenterState state,
  MovieSeries series,
) {
  return MovieRedesignCardData.fromSeries(series).copyWith(
    onTap: () => context.push(movieSeriesDetailRoute(series.id)),
    onPlay: () {
      final resume =
          state.continueWatching
              .where((item) => item.seriesId == series.id)
              .firstOrNull;
      final targetId = resume?.id;
      unawaited(
        context.push(
          targetId == null
              ? movieSeriesDetailRoute(series.id)
              : moviePlayRoute(targetId),
        ),
      );
    },
  );
}

String? _episodeLabelOf(MovieContinueWatching item) {
  final season = item.seasonNumber;
  final episode = item.episodeNumber;
  if (season == null || episode == null) {
    return null;
  }
  // 通用记法 SxxExx，固定两位。
  final seasonText = season.toString().padLeft(2, '0');
  final episodeText = episode.toString().padLeft(2, '0');
  return 'S${seasonText}E$episodeText';
}

/// 共用继续观看条目：分集补 SxxExx（主标题已是系列名）。
List<MovieRedesignContinueItem> _buildContinueItems(
  BuildContext context,
  MovieCenterState state,
) {
  return [
    for (final item in state.continueWatching)
      MovieRedesignContinueItem(
        data: item,
        episodeLabel: _episodeLabelOf(item),
        timeText: movieRedesignRelativeTime(context, item.updatedAt),
        onPlay: () => unawaited(context.push(moviePlayRoute(item.id))),
      ),
  ];
}

/// 继续观看横条：Movies / TV / Anime 共用；溢出横向滚动且隐藏滚动条。
Widget _sharedContinueStrip(
  BuildContext context,
  WidgetRef ref,
  MovieCenterState state,
) {
  final l10n = AppLocalizations.of(context);
  final items = _buildContinueItems(context, state);
  if (items.isEmpty) {
    return const SizedBox.shrink();
  }
  return MovieRedesignContinueStrip(
    title: l10n.videoSectionContinueWatching,
    subtitleEn: l10n.videoRedesignSubContinue,
    items: items,
    onViewAll:
        () => ref
            .read(movieCenterControllerProvider.notifier)
            .selectSection(MovieSection.continueWatching),
  );
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
    if (!mounted || !_scrollController.hasClients || _requestingNextPage) {
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _requestingNextPage = false;
        return;
      }
      unawaited(_loadNextPage());
    });
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
          padding: const EdgeInsets.only(top: 4),
          sliver: SliverToBoxAdapter(
            child: MovieRedesignSectionHeader(
              title: l10n.videoMovieLibrary,
              subtitleEn: l10n.videoRedesignSubMovies,
              count: filteredItems.isEmpty ? null : filteredItems.length,
              subtitle: l10n.videoMovieLibrarySubtitle,
            ),
          ),
        ),
        if (state.continueWatching.isNotEmpty)
          SliverPadding(
            padding: EdgeInsets.zero,
            sliver: SliverToBoxAdapter(
              child: _sharedContinueStrip(context, ref, state),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.only(bottom: 16),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MovieRedesignFilterSortBar(
                  filters: filters,
                  filterValue: state.filter.name,
                  onFilter: (value) {
                    controller.setFilter(
                      MovieLibraryFilter.values.firstWhere(
                        (f) => f.name == value,
                      ),
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
                if (state.searchQuery.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _SearchScopeNotice(loadedCount: state.movies.length),
                ],
              ],
            ),
          ),
        ),
        if (filteredItems.isEmpty)
          SliverPadding(
            padding: EdgeInsets.zero,
            sliver: SliverToBoxAdapter(
              child: MovieRedesignEmptyState(
                icon: Icons.movie_outlined,
                title: l10n.videoRedesignNoMatches,
                subtitle:
                    state.searchQuery.trim().isNotEmpty
                        ? l10n.videoSearchNoHitsLoadMore
                        : l10n.videoRedesignAdjustFilters,
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.zero,
            sliver: MovieRedesignPosterSliverGrid(
              items: [
                for (final item in filteredItems)
                  _movieCard(context, ref, item),
              ],
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(0, 24, 0, 48),
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

/// 搜索范围提示：本地过滤仅覆盖已加载分页，避免“库里有却搜不到”的误解。
class _SearchScopeNotice extends StatelessWidget {
  const _SearchScopeNotice({required this.loadedCount});

  final int loadedCount;

  @override
  Widget build(BuildContext context) {
    final palette = context.movieRedesign;
    final text = context.movieRedesignText;
    return Text(
      AppLocalizations.of(context).videoSearchScopeLoadedOnly(loadedCount),
      style: text.mono(
        size: 11,
        color: palette.mutedForeground.withValues(alpha: 0.85),
      ),
    );
  }
}

/// 剧集/动漫分区：系列海报网格，点击进剧集详情。
class _SeriesGridSection extends ConsumerWidget {
  const _SeriesGridSection({
    required this.title,
    required this.subtitleEn,
    required this.subtitle,
    required this.series,
    required this.anime,
  });

  final String title;
  final String subtitleEn;
  final String subtitle;
  final List<MovieSeries> series;

  /// 动漫分区标记：滚动加载取对应分页状态。
  final bool anime;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final centerState = ref.watch(movieCenterControllerProvider).requireValue;
    final controller = ref.read(movieCenterControllerProvider.notifier);
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
    final paging =
        anime ? centerState.animeSeriesPaging : centerState.tvSeriesPaging;
    return InfiniteScrollTrigger(
      enabled: paging.hasMore && !paging.isLoadingMore,
      onLoadMore: () => controller.loadMoreSeries(anime: anime),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.only(bottom: 16),
            sliver: SliverToBoxAdapter(
              child: MovieRedesignSectionHeader(
                title: title,
                subtitleEn: subtitleEn,
                count: series.isEmpty ? null : series.length,
                subtitle: subtitle,
              ),
            ),
          ),
          if (centerState.continueWatching.isNotEmpty)
            SliverPadding(
              padding: EdgeInsets.zero,
              sliver: SliverToBoxAdapter(
                child: _sharedContinueStrip(context, ref, centerState),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.only(bottom: 16),
            sliver: SliverToBoxAdapter(
              child: MovieRedesignFilterSortBar(
                filters: filters,
                filterValue: centerState.filter.name,
                onFilter: (value) {
                  controller.setFilter(
                    MovieLibraryFilter.values.firstWhere(
                      (f) => f.name == value,
                    ),
                  );
                },
                sorts: sorts,
                sortValue: centerState.sortBy.name,
                onSort: (value) {
                  controller.setSort(
                    MovieSortBy.values.firstWhere((s) => s.name == value),
                  );
                },
              ),
            ),
          ),
          if (series.isEmpty)
            SliverPadding(
              padding: EdgeInsets.zero,
              sliver: SliverToBoxAdapter(
                child: MovieRedesignEmptyState(
                  icon: Icons.tv_outlined,
                  title: l10n.videoNoMediaItems,
                ),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.zero,
              sliver: MovieRedesignPosterSliverGrid(
                items: [
                  for (final item in series)
                    _seriesCard(context, centerState, item),
                ],
              ),
            ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 48)),
        ],
      ),
    );
  }
}

/// 最近添加分区。
class _RecentSection extends ConsumerWidget {
  const _RecentSection({required this.state});

  final MovieCenterState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.only(bottom: 16),
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
            padding: EdgeInsets.zero,
            sliver: SliverToBoxAdapter(
              child: MovieRedesignEmptyState(
                icon: Icons.new_releases_outlined,
                title: l10n.videoNoMediaItems,
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.zero,
            sliver: MovieRedesignPosterSliverGrid(
              items: [
                for (final item in state.recentItems)
                  _movieCard(context, ref, item),
              ],
            ),
          ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 48)),
      ],
    );
  }
}

/// 继续观看分区：2/4 列进度卡片。
class _ContinueSection extends ConsumerWidget {
  const _ContinueSection({required this.state});

  final MovieCenterState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.only(bottom: 16),
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
            padding: EdgeInsets.zero,
            sliver: SliverToBoxAdapter(
              child: MovieRedesignEmptyState(
                icon: Icons.play_circle_outline_rounded,
                title: l10n.videoNoMediaItems,
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.zero,
            sliver: SliverToBoxAdapter(
              child: _ContinueCardWrap(
                items: _buildContinueItems(context, state),
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
        // 原型 gap-3 sm:gap-4。
        final gap = movieRedesignAtSm(width) ? 16.0 : 12.0;
        final cardWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final item in items)
              SizedBox(
                width: cardWidth,
                child: MovieRedesignContinueCard(item: item, compact: false),
              ),
          ],
        );
      },
    );
  }
}

/// 收藏分区。
class _FavoritesSection extends ConsumerWidget {
  const _FavoritesSection({required this.state});

  final MovieCenterState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // 影片收藏与系列（剧集/动漫）收藏合并展示；系列卡点击进系列详情。
    final totalCount = state.favoriteItems.length + state.favoriteSeries.length;
    final favoritesPaging = state.favoritesPaging;
    final favoriteSeriesPaging = state.favoriteSeriesPaging;
    return InfiniteScrollTrigger(
      enabled:
          (favoritesPaging.hasMore && !favoritesPaging.isLoadingMore) ||
          (favoriteSeriesPaging.hasMore && !favoriteSeriesPaging.isLoadingMore),
      onLoadMore: () {
        final controller = ref.read(movieCenterControllerProvider.notifier);
        if (favoritesPaging.hasMore && !favoritesPaging.isLoadingMore) {
          controller.loadMoreFavorites();
        }
        if (favoriteSeriesPaging.hasMore &&
            !favoriteSeriesPaging.isLoadingMore) {
          controller.loadMoreFavoriteSeries();
        }
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.only(bottom: 16),
            sliver: SliverToBoxAdapter(
              child: MovieRedesignSectionHeader(
                title: l10n.videoSectionFavorites,
                subtitleEn: l10n.videoRedesignSubFavorites,
                count: totalCount == 0 ? null : totalCount,
                subtitle: l10n.videoFavoritesSubtitle,
              ),
            ),
          ),
          if (totalCount == 0)
            SliverPadding(
              padding: EdgeInsets.zero,
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
              padding: EdgeInsets.zero,
              sliver: MovieRedesignPosterSliverGrid(
                items: [
                  for (final item in state.favoriteItems)
                    _movieCard(context, ref, item),
                  for (final series in state.favoriteSeries)
                    _seriesCard(context, state, series),
                ],
              ),
            ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 48)),
        ],
      ),
    );
  }
}
