part of 'movie_center_page.dart';

/// 剧集/动漫分区的托管形态（样例 Series 段）：chip 行 + 收藏覆盖 +
/// 海报轨；收藏为本地展示态，分页触发仅对非收藏列表生效。
class _HostedSeriesBody extends ConsumerStatefulWidget {
  const _HostedSeriesBody({
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
          SliverPadding(
            padding: const EdgeInsets.only(bottom: 16),
            sliver: SliverToBoxAdapter(
              child: MobileEnvSectionHeader(
                eyebrow: widget.subtitleEn,
                title: widget.title,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.only(bottom: 16),
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
                    for (final item in effective.take(12))
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
          const SliverPadding(padding: EdgeInsets.only(bottom: 48)),
        ],
      ),
    );
  }
}
