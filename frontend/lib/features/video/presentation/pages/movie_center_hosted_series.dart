part of 'movie_center_page.dart';

/// 剧集/动漫分区的托管形态（样例 Series 段）：chip 行 + 收藏覆盖 +
/// 海报轨；收藏为本地展示态，分页触发仅对非收藏列表生效。
/// 段内不渲染标题栏，计数与分区名由壳层模块头与上方分段条承担。
class _HostedSeriesBody extends ConsumerStatefulWidget {
  const _HostedSeriesBody({required this.series, required this.anime});

  final List<MovieSeries> series;
  final bool anime;

  @override
  ConsumerState<_HostedSeriesBody> createState() => _HostedSeriesBodyState();
}

class _HostedSeriesBodyState extends ConsumerState<_HostedSeriesBody> {
  bool _favoritesOnly = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final centerState = ref.watch(movieCenterControllerProvider).requireValue;
    final controller = ref.read(movieCenterControllerProvider.notifier);
    final effective =
        _favoritesOnly ? centerState.favoriteSeries : widget.series;
    final paging =
        widget.anime
            ? centerState.animeSeriesPaging
            : centerState.tvSeriesPaging;
    return InfiniteScrollTrigger(
      enabled: !_favoritesOnly && paging.hasMore && !paging.isLoadingMore,
      onLoadMore: () => controller.loadMoreSeries(anime: widget.anime),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          // 样例 `.chip-row` 外边距 2px 0 14px，同样坐在 main 的 20px 页边距里。
          // 样例只给 Films/Series 两档画了这行，动漫档是稿子的空洞：
          // 排序与状态筛选在动漫档同样可用，保留而不按空洞删。
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 14),
            sliver: SliverToBoxAdapter(
              child: MovieRedesignMobileChips(
                sortBy: centerState.sortBy,
                onSortBy: controller.setSort,
                favoritesOnly: _favoritesOnly,
                onFavoritesOnly:
                    (value) => setState(() => _favoritesOnly = value),
                filter: centerState.filter,
                onFilter: controller.setFilter,
              ),
            ),
          ),
          if (effective.isEmpty)
            SliverPadding(
              padding: EdgeInsets.zero,
              sliver: SliverToBoxAdapter(
                child: EnvEmptyState(
                  icon: OmniIcons.film,
                  title: l10n.videoNoMediaItems,
                  message:
                      _favoritesOnly
                          ? l10n.videoRedesignNoFavoritesHint
                          : centerState.searchQuery.trim().isNotEmpty
                          ? l10n.videoSearchNoHitsLoadMore
                          : l10n.videoRedesignAdjustFilters,
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.only(top: 6),
              sliver: SliverToBoxAdapter(
                child: SampleRail(
                  children: [
                    for (final item in effective)
                      SamplePosterCard(
                        imageUrl: item.posterUrl,
                        title: item.title,
                        subtitle: item.firstAirDate?.year.toString() ?? '',
                        badge: SampleSeriesBadge(
                          label:
                              widget.anime
                                  ? l10n.videoSectionAnime
                                  : l10n.videoSectionSeries,
                        ),
                        onTap:
                            () => context.push(movieSeriesDetailRoute(item.id)),
                      ),
                  ],
                ),
              ),
            ),
          if (!_favoritesOnly && paging.hasMore)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              sliver: SliverToBoxAdapter(
                child: Center(
                  child: TextButton(
                    // 加载中同样渲染按钮但禁用：静态可点区域，不加第二个转圈。
                    onPressed:
                        paging.isLoadingMore
                            ? null
                            : () =>
                                controller.loadMoreSeries(anime: widget.anime),
                    child: Text(l10n.videoSeriesLoadMore),
                  ),
                ),
              ),
            ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 48)),
        ],
      ),
    );
  }
}
