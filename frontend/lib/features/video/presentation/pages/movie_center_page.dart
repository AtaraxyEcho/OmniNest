import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/search/scoped_search_source.dart';
import 'package:omninest/core/widgets/infinite_scroll.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/mobile_env_colors.dart';
import 'package:omninest/core/auth/user_capabilities.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/widgets/app_error_view.dart';
import 'package:omninest/core/widgets/app_loading.dart';
import 'package:omninest/core/widgets/env_empty_state.dart';
import 'package:omninest/core/widgets/omni_icons.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/domain/movie_detail_routes.dart';
import 'package:omninest/features/video/domain/movie_library_models.dart';
import 'package:omninest/features/video/presentation/theme/movie_redesign_theme.dart';
import 'package:omninest/features/video/presentation/widgets/redesign/movie_redesign_mobile_chips.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/core/widgets/mobile_sample_kit.dart';
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
part 'movie_center_sample_rails.dart';
part 'movie_center_hosted_series.dart';

class MovieCenterPage extends ConsumerStatefulWidget {
  const MovieCenterPage({this.initialSection, super.key});

  /// 深链直达的分区（工具总入口按分区进入）；为空时托管态落 For you。
  final MovieSection? initialSection;

  @override
  ConsumerState<MovieCenterPage> createState() => _MovieCenterPageState();
}

class _MovieCenterPageState extends ConsumerState<MovieCenterPage> {
  // 进入页面的重进刷新节流：provider 常驻内存，posterUrl 是 2h/6h 的
  // 临时地址，不刷新则过期后海报灰块；15s 内往返不重复拉取。
  static DateTime? _lastEntryRefreshAt;
  bool _hostedScope = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _hostedScope = MobileShellScope.isHosted(context);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final controller = ref.read(movieCenterControllerProvider.notifier);
      // 进入即定位第一栏 For you（托管态），深链带分区时以深链为准：
      // 先同步切分区再刷新，单一写入顺序——此前一次性切栏与 refresh 并发，
      // refresh 以旧分区（电影）回写，造成落地电影档/返回观感来回切换。
      final entrySection = widget.initialSection;
      if (entrySection != null) {
        controller.selectSection(entrySection);
      } else if (_hostedScope) {
        controller.selectSection(MovieSection.continueWatching);
      }
      final now = DateTime.now();
      final last = _lastEntryRefreshAt;
      if (last != null && now.difference(last) < const Duration(seconds: 15)) {
        return;
      }
      _lastEntryRefreshAt = now;
      unawaited(controller.refresh());
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(movieCenterControllerProvider);
    // 托管态底由环境层绘制，异常/骨架页不再压一块重设计实底。
    final pageBackground =
        MobileShellScope.isHosted(context)
            ? Colors.transparent
            : context.movieRedesign.background;
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
            backgroundColor: pageBackground,
            body: AppErrorView(
              message: describeUserFacingError(error).displayMessage,
              onRetry: () => ref.invalidate(movieCenterControllerProvider),
            ),
          ),
      loading:
          () => Scaffold(
            backgroundColor: pageBackground,
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
        // 服务端影视库关键词有 200 字上限，超长输入会变成一次被拒的请求；
        // 限在输入侧，框里的文本才等于真正打出去的关键词。
        inputFormatters: <TextInputFormatter>[
          LengthLimitingTextInputFormatter(ScopedSearchLimits.maxQueryLength),
        ],
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
      // 托管态走环境空态族；工位态保留原图标加文案块，两形态各按自己的
      // 密度排布，不为统一而把工位块放大。
      return MobileShellScope.isHosted(context)
          ? EnvEmptyState(
            icon: OmniIcons.settings,
            title: l10n.videoManageAdminOnly,
          )
          : _ManagementAccessDenied(l10n: l10n);
    }
    if (state.loadingSections.contains(state.section) &&
        !state.loadedSections.contains(state.section)) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: AppLoading.grid(gridAspectRatio: 0.62),
      );
    }
    // 无 activity:write 的角色隐藏删历史入口，只保留浏览；托管与工位共用
    // 同一组回调，避免两处能力判断漂移。
    final canManageActivity =
        ref.watch(userCapabilitiesProvider).canManageOwnActivity;
    final historyController = ref.read(movieCenterControllerProvider.notifier);
    final ValueChanged<MovieWatchHistory>? onHistoryDelete =
        canManageActivity
            ? (entry) => historyController.deleteHistoryItem(entry)
            : null;
    final VoidCallback? onHistoryClear =
        canManageActivity ? () => historyController.clearHistory() : null;
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
      MovieSection.collections =>
        MobileShellScope.isHosted(context)
            ? Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: HostedCollectionsSection(collections: state.collections),
            )
            : CollectionsSection(
              totalCount: state.movies.length,
              collections: state.collections,
            ),
      MovieSection.recent => _RecentSection(state: state),
      MovieSection.continueWatching => _ContinueSection(state: state),
      MovieSection.favorites => _FavoritesSection(state: state),
      MovieSection.history =>
        MobileShellScope.isHosted(context)
            ? Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: HostedHistorySection(
                items: state.watchHistory,
                isLoadingMore: state.historyPaging.isLoadingMore,
                onDelete: onHistoryDelete,
                onClearAll: onHistoryClear,
              ),
            )
            : HistorySection(
              items: state.watchHistory,
              hasMore: state.historyPaging.hasMore,
              isLoadingMore: state.historyPaging.isLoadingMore,
              onLoadMore: () => historyController.loadMoreHistory(),
              onDelete: onHistoryDelete,
              onClearAll: onHistoryClear,
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
  bool _favoritesOnly = false;

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
    final hosted = MobileShellScope.isHosted(context);
    // 收藏 chip 为移动本地展示态：直接切 favoriteItems 网格。
    final filteredItems =
        hosted && _favoritesOnly ? state.favoriteItems : state.filteredMovies;
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
        // 托管态不渲染档内标题栏：样例影视视图把计数放在模块头副题，
        // 分段条已在壳层与内容之间，段内再出一条同名标题即重复。
        if (!hosted)
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
        if (!hosted && state.continueWatching.isNotEmpty)
          SliverPadding(
            padding: EdgeInsets.zero,
            sliver: SliverToBoxAdapter(
              child: _sharedContinueStrip(context, ref, state),
            ),
          ),
        SliverPadding(
          // 样例 `.chip-row` 外边距 2px 0 14px；工位排序条保持原内衬。
          padding:
              hosted
                  ? const EdgeInsets.fromLTRB(0, 2, 0, 14)
                  : const EdgeInsets.only(bottom: 16),
          sliver: SliverToBoxAdapter(
            child:
                hosted
                    ? MovieRedesignMobileChips(
                      sortBy: state.sortBy,
                      onSortBy: controller.setSort,
                      favoritesOnly: _favoritesOnly,
                      onFavoritesOnly:
                          (value) => setState(() => _favoritesOnly = value),
                      filter: state.filter,
                      onFilter: controller.setFilter,
                    )
                    : Column(
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
                              MovieSortBy.values.firstWhere(
                                (s) => s.name == value,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
          ),
        ),
        if (hosted && _favoritesOnly)
          _hostedFilmRows(filteredItems)
        else if (filteredItems.isEmpty)
          SliverPadding(
            padding: EdgeInsets.zero,
            sliver: SliverToBoxAdapter(
              child:
                  hosted
                      // 托管态空态走样例 .empty-action 玻璃族。
                      ? EnvEmptyState(
                        icon: OmniIcons.film,
                        title: l10n.videoRedesignNoMatches,
                        message: l10n.videoRedesignAdjustFilters,
                      )
                      : MovieRedesignEmptyState(
                        icon: Icons.movie_outlined,
                        title: l10n.videoRedesignNoMatches,
                        subtitle: l10n.videoRedesignAdjustFilters,
                      ),
            ),
          )
        else if (hosted)
          _hostedFilmRows(filteredItems)
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
    // 托管态走移动形态（chip 行 + 收藏本地覆盖），桌面路径零变化。
    if (MobileShellScope.isHosted(context)) {
      return _HostedSeriesBody(series: series, anime: anime);
    }
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

/// 取 hero 项自身的影片条目：For-you 不保证已加载影片分页，因此在已加载的
/// 影片列表与最近添加中按 id 查；两处都没有时返回 null，元数据行不渲染。
MovieVideoItem? _heroSourceMovie(MovieCenterState state, String id) {
  for (final source in <List<MovieVideoItem>>[
    state.movies,
    state.recentItems,
  ]) {
    final match = source.where((item) => item.id == id).firstOrNull;
    if (match != null) {
      return match;
    }
  }
  return null;
}

/// hero 眉标：有续播进度时显示进度与剩余时长，无进度时显示样例的精选标注。
String _heroEyebrowLabel(AppLocalizations l10n, MovieContinueWatching? item) {
  if (item == null) {
    return '${l10n.videoHeroFeatured.toUpperCase()} · '
        '${l10n.videoHeroMovie.toUpperCase()}';
  }
  final progress = item.progressPercent.clamp(0.0, 100.0).round();
  final remainingMinutes =
      (item.durationSeconds - item.positionSeconds).clamp(
        0,
        item.durationSeconds,
      ) ~/
      60;
  return '${l10n.videoSectionContinueWatching.toUpperCase()} · $progress% · '
      '${l10n.videoHeroMinutesLeft(remainingMinutes)}';
}

/// 续播项的分集标注；元数据未入库时用它代替影片摘要行。
String? _heroEpisodeLabel(MovieContinueWatching? item) {
  final seriesId = item?.seriesId;
  if (item == null || seriesId == null || seriesId.isEmpty) {
    return null;
  }
  final season = item.seasonNumber;
  final episode = item.episodeNumber;
  if (season == null || episode == null) {
    return null;
  }
  return 'S$season E$episode';
}

/// 继续观看分区：2/4 列进度卡片。
class _ContinueSection extends ConsumerWidget {
  const _ContinueSection({required this.state});

  final MovieCenterState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // 托管态即移动四段中的 For you：影院 hero（精选位）+ 续播横条。
    if (MobileShellScope.isHosted(context)) {
      final continueItem = state.continueWatching.firstOrNull;
      // 样例 cinema-hero 是精选位，不因无续播记录而整块消失：无续播时退到
      // 最近添加首项。元数据与徽标一律绑 hero 项自身，否则会出现
      // 「A 的标题配 B 的评分」。
      final heroMovie =
          continueItem == null
              ? state.recentItems.firstOrNull
              : _heroSourceMovie(state, continueItem.id);
      final heroId = continueItem?.id ?? heroMovie?.id;
      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          if (heroId != null)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 26),
              sliver: SliverToBoxAdapter(
                child: MovieMobileCinemaHero(
                  title: continueItem?.title ?? heroMovie!.title,
                  posterUrl: continueItem?.posterUrl ?? heroMovie?.posterUrl,
                  eyebrow: _heroEyebrowLabel(l10n, continueItem),
                  primaryLabel:
                      continueItem == null
                          ? l10n.videoHeroWatchNow
                          : l10n.videoHeroResume,
                  metaLine:
                      heroMovie == null
                          ? _heroEpisodeLabel(continueItem)
                          : _movieCardSubtitle(heroMovie),
                  badgeText: _movieBadgeText(heroMovie),
                  onPlay: () => unawaited(context.push(moviePlayRoute(heroId))),
                  onInfo:
                      () => unawaited(
                        context.push(
                          movieDetailRouteFromIds(
                            videoItemId: heroId,
                            seriesId:
                                continueItem?.seriesId ?? heroMovie?.seriesId,
                          ),
                        ),
                      ),
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.only(left: 20),
            sliver: SliverToBoxAdapter(
              child: _hostedContinueRail(context, state),
            ),
          ),
          if (state.continueWatching.isEmpty)
            SliverPadding(
              padding: EdgeInsets.zero,
              sliver: SliverToBoxAdapter(
                child: EnvEmptyState(
                  icon: OmniIcons.play,
                  title: l10n.videoNoMediaItems,
                  message: l10n.videoRedesignNoHistoryHint,
                ),
              ),
            ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 48)),
        ],
      );
    }
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
