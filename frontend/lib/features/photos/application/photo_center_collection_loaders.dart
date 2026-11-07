part of 'photo_controller.dart';

/// 照片中心各集合加载统一使用的分页大小。
const int _photoCenterPageSize = 50;

/// 照片中心的分页、时间线、分组与关系图谱加载命令。
mixin PhotoCenterCollectionLoaders on AsyncNotifier<PhotoCenterState> {
  PhotoRepository get _repo;

  /// 加载当前照片页签的下一页。
  Future<void> loadMoreVisiblePhotos() async {
    final current = state.asData?.value;
    if (current == null) return;
    switch (current.tab) {
      case PhotoTab.all:
        await _loadMorePhotos(favorites: false);
        return;
      case PhotoTab.favorites:
        await _loadMorePhotos(favorites: true);
        return;
    }
  }

  Future<void> _loadMorePhotos({required bool favorites}) async {
    final current = state.asData?.value;
    if (current == null) return;
    final loading =
        favorites
            ? current.isLoadingMoreFavorites
            : current.isLoadingMorePhotos;
    final hasMore =
        favorites ? current.hasMoreFavorites : current.hasMorePhotos;
    if (loading || !hasMore) return;
    final expectedQuery = current.searchQuery.trim();
    final expectedTab = current.tab;
    final nextPage =
        favorites ? current.favoritePage + 1 : current.photoPage + 1;
    state = AsyncData(
      current.copyWith(
        isLoadingMoreFavorites: favorites ? true : null,
        isLoadingMorePhotos: favorites ? null : true,
        clearFavoritePageError: favorites,
        clearPhotoPageError: !favorites,
      ),
    );
    try {
      final page =
          favorites
              ? await _repo.listFavorites(
                query: expectedQuery,
                page: nextPage,
                size: _photoCenterPageSize,
              )
              : await _repo.listPhotos(
                query: expectedQuery,
                page: nextPage,
                size: _photoCenterPageSize,
              );
      final latest = state.asData?.value;
      if (latest == null ||
          latest.tab != expectedTab ||
          latest.searchQuery.trim() != expectedQuery) {
        return;
      }
      state = AsyncData(
        favorites
            ? latest.copyWith(
              favorites: _appendUnique(latest.favorites, page.items),
              favoritePage: page.page,
              favoriteTotalElements: page.totalElements,
              isLoadingMoreFavorites: false,
            )
            : latest.copyWith(
              photos: _appendUnique(latest.photos, page.items),
              photoPage: page.page,
              photoTotalElements: page.totalElements,
              isLoadingMorePhotos: false,
            ),
      );
    } on Exception catch (error) {
      final latest = state.asData?.value;
      if (latest == null) return;
      final message = userFacingErrorText(error);
      state = AsyncData(
        favorites
            ? latest.copyWith(
              isLoadingMoreFavorites: false,
              favoritePageError: message,
            )
            : latest.copyWith(
              isLoadingMorePhotos: false,
              photoPageError: message,
            ),
      );
    }
  }

  Future<void> _reloadVisiblePage(PhotoTab tab, String query) async {
    try {
      final page =
          tab == PhotoTab.favorites
              ? await _repo.listFavorites(
                query: query,
                size: _photoCenterPageSize,
              )
              : await _repo.listPhotos(
                query: query,
                size: _photoCenterPageSize,
              );
      final latest = state.asData?.value;
      if (latest == null || latest.tab != tab || latest.searchQuery != query) {
        return;
      }
      state = AsyncData(
        tab == PhotoTab.favorites
            ? latest.copyWith(
              favorites: page.items,
              favoritePage: page.page,
              favoriteTotalElements: page.totalElements,
              favoriteRefreshVersion: latest.favoriteRefreshVersion + 1,
              clearFavoritePageError: true,
            )
            : latest.copyWith(
              photos: page.items,
              photoPage: page.page,
              photoTotalElements: page.totalElements,
              photoRefreshVersion: latest.photoRefreshVersion + 1,
              clearPhotoPageError: true,
            ),
      );
    } on Exception catch (error) {
      final latest = state.asData?.value;
      if (latest == null || latest.tab != tab || latest.searchQuery != query) {
        return;
      }
      final message = userFacingErrorText(error);
      state = AsyncData(
        tab == PhotoTab.favorites
            ? latest.copyWith(favoritePageError: message)
            : latest.copyWith(photoPageError: message),
      );
    }
  }

  List<PhotoItem> _appendUnique(
    List<PhotoItem> existing,
    List<PhotoItem> incoming,
  ) {
    final seen = existing.map((item) => item.id).toSet();
    return <PhotoItem>[
      ...existing,
      ...incoming.where((item) => seen.add(item.id)),
    ];
  }

  List<PhotoItem> _mergeRefreshedPage(
    List<PhotoItem> existing,
    List<PhotoItem> firstPage,
    int totalElements,
  ) {
    final merged = _appendUnique(firstPage, existing);
    var targetLength =
        existing.length > firstPage.length ? existing.length : firstPage.length;
    if (targetLength > totalElements) {
      targetLength = totalElements;
    }
    return merged.take(targetLength).toList(growable: false);
  }

  /// 加载首个时间线月份页。
  Future<void> loadTimeline({bool force = false}) async {
    final current = state.asData?.value;
    if (current == null) return;
    if (current.timeline != null && !force) return;
    try {
      final page = await _repo.getTimeline(size: _photoCenterPageSize);
      final latest = state.asData?.value;
      if (latest == null) return;
      final entries =
          force && latest.timeline != null
              ? _mergeRefreshedTimeline(
                latest.timeline!.monthEntries,
                page.items,
                page.totalElements,
              )
              : page.items;
      state = AsyncData(
        latest.copyWith(
          timeline: PhotoTimeline.fromMonthEntries(entries),
          timelinePage: force ? latest.timelinePage : page.page,
          timelineTotalElements: page.totalElements,
          clearTimelinePageError: true,
        ),
      );
    } on Exception catch (e) {
      final latest = state.asData?.value;
      if (latest != null) {
        state = AsyncData(
          latest.copyWith(
            timelinePageError: userFacingErrorText(e),
          ),
        );
      }
    }
  }

  /// 加载下一页时间线月份，并保留当前滚动位置。
  Future<void> loadMoreTimeline() async {
    final current = state.asData?.value;
    if (current == null ||
        current.timeline == null ||
        current.isLoadingMoreTimeline ||
        !current.hasMoreTimeline) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        isLoadingMoreTimeline: true,
        clearTimelinePageError: true,
      ),
    );
    try {
      final page = await _repo.getTimeline(
        page: current.timelinePage + 1,
        size: _photoCenterPageSize,
      );
      final latest = state.asData?.value;
      if (latest == null || latest.timeline == null) return;
      final entries = _appendUniqueTimeline(
        latest.timeline!.monthEntries,
        page.items,
      );
      state = AsyncData(
        latest.copyWith(
          timeline: PhotoTimeline.fromMonthEntries(entries),
          timelinePage: page.page,
          timelineTotalElements: page.totalElements,
          isLoadingMoreTimeline: false,
          clearTimelinePageError: true,
        ),
      );
    } on Exception catch (e) {
      final latest = state.asData?.value;
      if (latest != null) {
        state = AsyncData(
          latest.copyWith(
            isLoadingMoreTimeline: false,
            timelinePageError: userFacingErrorText(e),
          ),
        );
      }
    }
  }

  List<PhotoTimelineMonthEntry> _appendUniqueTimeline(
    List<PhotoTimelineMonthEntry> existing,
    List<PhotoTimelineMonthEntry> incoming,
  ) {
    final seen = existing.map((item) => item.key).toSet();
    return [...existing, ...incoming.where((item) => seen.add(item.key))];
  }

  List<PhotoTimelineMonthEntry> _mergeRefreshedTimeline(
    List<PhotoTimelineMonthEntry> existing,
    List<PhotoTimelineMonthEntry> firstPage,
    int totalElements,
  ) {
    final seen = firstPage.map((item) => item.key).toSet();
    final merged = [
      ...firstPage,
      ...existing.where((item) => seen.add(item.key)),
    ];
    var targetLength =
        existing.length > firstPage.length ? existing.length : firstPage.length;
    if (targetLength > totalElements) targetLength = totalElements;
    return merged.take(targetLength).toList(growable: false);
  }

  /// 加载关系图谱节点与边（自洽数据，不依赖分页列表）。
  Future<void> loadRelationGraph({bool force = false}) async {
    final current = state.asData?.value;
    if (current == null) return;
    if (!force && current.relationGraph.nodes.isNotEmpty) return;
    if (current.isLoadingRelationGraph) return;
    state = AsyncData(
      current.copyWith(
        isLoadingRelationGraph: true,
        clearRelationGraphError: true,
      ),
    );
    try {
      final graph = await _repo.getRelationGraph();
      final latest = state.asData?.value;
      if (latest == null) return;
      state = AsyncData(
        latest.copyWith(
          relationGraph: graph,
          isLoadingRelationGraph: false,
          clearRelationGraphError: true,
        ),
      );
    } on Exception catch (e) {
      final latest = state.asData?.value;
      if (latest != null) {
        state = AsyncData(
          latest.copyWith(
            isLoadingRelationGraph: false,
            relationGraphError: userFacingErrorText(e),
          ),
        );
      }
    }
  }

  /// 加载指定维度的首个分组页。
  Future<void> loadGroups(GroupBy by, {bool force = false}) async {
    final current = state.asData?.value;
    if (current == null) return;
    if (current.groups != null && current.groupBy == by && !force) return;
    state = AsyncData(
      current.copyWith(
        groups: current.groupBy == by ? current.groups : const [],
        groupBy: by,
        isLoadingGroups: true,
        isLoadingMoreGroups: false,
        clearGroupPageError: true,
      ),
    );
    try {
      final page = await _repo.getGroups(by.value, size: _photoCenterPageSize);
      final latest = state.asData?.value;
      if (latest == null || latest.groupBy != by) return;
      final groups =
          force && latest.groups != null
              ? _mergeRefreshedGroups(
                latest.groups!,
                page.items,
                page.totalElements,
              )
              : page.items;
      state = AsyncData(
        latest.copyWith(
          groups: groups,
          groupBy: by,
          groupPage: force ? latest.groupPage : page.page,
          groupTotalElements: page.totalElements,
          isLoadingGroups: false,
          clearGroupPageError: true,
        ),
      );
    } on Exception catch (e) {
      final latest = state.asData?.value;
      if (latest != null && latest.groupBy == by) {
        state = AsyncData(
          latest.copyWith(
            isLoadingGroups: false,
            groupPageError: userFacingErrorText(e),
          ),
        );
      }
    }
  }

  /// 加载当前维度的下一页分组。
  Future<void> loadMoreGroups() async {
    final current = state.asData?.value;
    if (current == null ||
        current.groups == null ||
        current.isLoadingGroups ||
        current.isLoadingMoreGroups ||
        !current.hasMoreGroups) {
      return;
    }
    state = AsyncData(
      current.copyWith(isLoadingMoreGroups: true, clearGroupPageError: true),
    );
    try {
      final page = await _repo.getGroups(
        current.groupBy.value,
        page: current.groupPage + 1,
        size: _photoCenterPageSize,
      );
      final latest = state.asData?.value;
      if (latest == null || latest.groupBy != current.groupBy) return;
      state = AsyncData(
        latest.copyWith(
          groups: _appendUniqueGroups(latest.groups ?? const [], page.items),
          groupPage: page.page,
          groupTotalElements: page.totalElements,
          isLoadingMoreGroups: false,
          clearGroupPageError: true,
        ),
      );
    } on Exception catch (e) {
      final latest = state.asData?.value;
      if (latest != null && latest.groupBy == current.groupBy) {
        state = AsyncData(
          latest.copyWith(
            isLoadingMoreGroups: false,
            groupPageError: userFacingErrorText(e),
          ),
        );
      }
    }
  }

  List<PhotoGroup> _appendUniqueGroups(
    List<PhotoGroup> existing,
    List<PhotoGroup> incoming,
  ) {
    final seen = existing.map((group) => group.groupKey).toSet();
    return [
      ...existing,
      ...incoming.where((group) => seen.add(group.groupKey)),
    ];
  }

  List<PhotoGroup> _mergeRefreshedGroups(
    List<PhotoGroup> existing,
    List<PhotoGroup> firstPage,
    int totalElements,
  ) {
    final seen = firstPage.map((group) => group.groupKey).toSet();
    final merged = [
      ...firstPage,
      ...existing.where((group) => seen.add(group.groupKey)),
    ];
    var targetLength =
        existing.length > firstPage.length ? existing.length : firstPage.length;
    if (targetLength > totalElements) targetLength = totalElements;
    return merged.take(targetLength).toList(growable: false);
  }
}
