part of 'movie_controller.dart';

/// 影视中心的分页续载段；状态读写经 centerState/centerRef 出口。
extension MovieCenterPaging on MovieCenterController {
  /// 通用续页：拉取 page+1 追加去重；门闩经 [onPaging] 回写状态，
  /// 失败回滚等待下次触底。
  Future<void> _appendPage<T>({
    required List<T> currentItems,
    required ListPaging paging,
    required String Function(T item) keyOf,
    required Future<MediaPage<T>> Function(int page) fetch,
    required void Function(ListPaging paging) onPaging,
    required void Function(List<T> items, ListPaging paging) apply,
  }) async {
    if (!paging.hasMore || paging.isLoadingMore) {
      return;
    }
    onPaging(paging.copyWith(isLoadingMore: true));
    try {
      final next = await fetch(paging.page + 1);
      final seen = currentItems.map(keyOf).toSet();
      apply(<T>[
        ...currentItems,
        ...next.items.where((item) => !seen.contains(keyOf(item))),
      ], _pagingOf(next));
    } on Exception {
      onPaging(paging);
    }
  }

  /// 观看历史续页。
  Future<void> loadMoreHistory() async {
    final current = centerState.asData?.value;
    if (current == null) {
      return;
    }
    await _appendPage(
      currentItems: current.watchHistory,
      paging: current.historyPaging,
      keyOf: (item) => item.id,
      fetch: (page) => _api.historyPage(page: page),
      onPaging: (paging) => _setHistoryPaging(paging),
      apply: (items, paging) {
        final latest = centerState.asData?.value;
        if (latest != null) {
          centerState = AsyncData(
            latest.copyWith(watchHistory: items, historyPaging: paging),
          );
        }
      },
    );
  }

  /// 确保收藏条目已加载。
  ///
  /// 收藏 chip 是电影分区内的本地视图，而收藏列表只在进入收藏分区时取数：
  /// 从未访问过收藏分区时 [favoritesPaging] 的 page 仍是 -1，直接切视图只会
  /// 得到空网格，且续页门闩为 false 永远不再请求。
  Future<void> ensureFavoritesLoaded() async {
    final current = centerState.asData?.value;
    if (current == null || current.favoritesPaging.page >= 0) {
      return;
    }
    await _loadSection(MovieSection.favorites);
  }

  /// 收藏视频续页。
  Future<void> loadMoreFavorites() async {
    final current = centerState.asData?.value;
    if (current == null) {
      return;
    }
    await _appendPage(
      currentItems: current.favoriteItems,
      paging: current.favoritesPaging,
      keyOf: (item) => item.id,
      fetch: (page) => _api.favoritesPage(page: page),
      onPaging: (paging) => _setFavoritesPaging(paging),
      apply: (items, paging) {
        final latest = centerState.asData?.value;
        if (latest != null) {
          centerState = AsyncData(
            latest.copyWith(favoriteItems: items, favoritesPaging: paging),
          );
        }
      },
    );
  }

  /// 收藏系列续页。
  Future<void> loadMoreFavoriteSeries() async {
    final current = centerState.asData?.value;
    if (current == null) {
      return;
    }
    await _appendPage(
      currentItems: current.favoriteSeries,
      paging: current.favoriteSeriesPaging,
      keyOf: (item) => item.id,
      fetch: (page) => _api.favoriteSeriesPage(page: page),
      onPaging: (paging) => _setFavoriteSeriesPaging(paging),
      apply: (items, paging) {
        final latest = centerState.asData?.value;
        if (latest != null) {
          centerState = AsyncData(
            latest.copyWith(
              favoriteSeries: items,
              favoriteSeriesPaging: paging,
            ),
          );
        }
      },
    );
  }

  /// 剧集/动漫系列网格续页。
  Future<void> loadMoreSeries({required bool anime}) async {
    final current = centerState.asData?.value;
    if (current == null) {
      return;
    }
    await _appendPage(
      currentItems: anime ? current.animeSeries : current.tvSeries,
      paging: anime ? current.animeSeriesPaging : current.tvSeriesPaging,
      keyOf: (item) => item.id,
      fetch:
          (page) => _api.seriesByTypePage(
            seriesType: anime ? 'ANIME' : 'TV',
            page: page,
          ),
      onPaging: (paging) => _setSeriesPaging(anime: anime, paging: paging),
      apply: (items, paging) {
        final latest = centerState.asData?.value;
        if (latest != null) {
          centerState = AsyncData(
            anime
                ? latest.copyWith(animeSeries: items, animeSeriesPaging: paging)
                : latest.copyWith(tvSeries: items, tvSeriesPaging: paging),
          );
        }
      },
    );
  }

  void _setHistoryPaging(ListPaging paging) {
    final latest = centerState.asData?.value;
    if (latest != null) {
      centerState = AsyncData(latest.copyWith(historyPaging: paging));
    }
  }

  void _setFavoritesPaging(ListPaging paging) {
    final latest = centerState.asData?.value;
    if (latest != null) {
      centerState = AsyncData(latest.copyWith(favoritesPaging: paging));
    }
  }

  void _setFavoriteSeriesPaging(ListPaging paging) {
    final latest = centerState.asData?.value;
    if (latest != null) {
      centerState = AsyncData(latest.copyWith(favoriteSeriesPaging: paging));
    }
  }

  void _setSeriesPaging({required bool anime, required ListPaging paging}) {
    final latest = centerState.asData?.value;
    if (latest != null) {
      centerState = AsyncData(
        anime
            ? latest.copyWith(animeSeriesPaging: paging)
            : latest.copyWith(tvSeriesPaging: paging),
      );
    }
  }
}
