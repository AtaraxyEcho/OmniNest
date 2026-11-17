part of 'movie_center_page.dart';

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

/// 分区徽标计数：优先取服务端总数，分区还没加载过（total 为 -1）时退回已加载长度。
int _pagingCount(ListPaging paging, int loadedCount) =>
    paging.total >= 0 ? paging.total : loadedCount;
