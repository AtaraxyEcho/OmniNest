part of 'movie_controller.dart';

/// 影视中心的查询条件与条目、收藏、合集命令段；状态与加载留在主文件。
extension MovieCenterCommands on MovieCenterController {
  void selectSection(MovieSection section) {
    _searchDebounce?.cancel();
    centerRef.read(movieCenterSectionProvider.notifier).select(section);
    final current = centerState.asData?.value;
    if (current == null) {
      // controller 正在重建（如 apply 完成后实时刷新）：记录待恢复分区，
      // build() 完成后会从 provider / pending 恢复，避免点击被静默丢弃。
      _pendingSection = section;
      return;
    }
    _pendingSection = null;
    centerState = AsyncData(
      current.copyWith(
        section: section,
        searchQuery: '',
        filter: MovieLibraryFilter.all,
        selectedGenres: {},
        clearYearFrom: true,
        clearYearTo: true,
        clearMinRating: true,
      ),
    );
    unawaited(_loadSection(section));
  }

  void setSearchQuery(String query) {
    // 防抖：避免每键一次触发全库 filter/sort 与整页重建。
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      final current = centerState.asData?.value;
      if (current == null || current.searchQuery == query) {
        return;
      }
      centerState = AsyncData(current.copyWith(searchQuery: query));
    });
  }

  void cancelSearchDebounce() {
    _searchDebounce?.cancel();
  }

  void setFilter(MovieLibraryFilter filter) {
    final current = centerState.asData?.value;
    if (current == null) {
      return;
    }
    centerState = AsyncData(current.copyWith(filter: filter));
  }

  void toggleGenre(String genre) {
    final current = centerState.asData?.value;
    if (current == null) {
      return;
    }
    final genres = Set<String>.from(current.selectedGenres);
    if (genres.contains(genre)) {
      genres.remove(genre);
    } else {
      genres.add(genre);
    }
    centerState = AsyncData(current.copyWith(selectedGenres: genres));
  }

  void setYearRange({int? from, int? to}) {
    final current = centerState.asData?.value;
    if (current == null) {
      return;
    }
    centerState = AsyncData(
      current.copyWith(
        yearFrom: from,
        yearTo: to,
        clearYearFrom: from == null && current.yearFrom != null,
        clearYearTo: to == null && current.yearTo != null,
      ),
    );
  }

  void setMinRating(double? rating) {
    final current = centerState.asData?.value;
    if (current == null) {
      return;
    }
    centerState = AsyncData(
      current.copyWith(
        minRating: rating,
        clearMinRating: rating == null && current.minRating != null,
      ),
    );
  }

  void clearFilters() {
    final current = centerState.asData?.value;
    if (current == null) {
      return;
    }
    centerState = AsyncData(
      current.copyWith(
        selectedGenres: {},
        clearYearFrom: true,
        clearYearTo: true,
        clearMinRating: true,
      ),
    );
  }

  void setSort(MovieSortBy sortBy, {bool? ascending}) {
    final current = centerState.asData?.value;
    if (current == null) return;
    centerState = AsyncData(
      current.copyWith(
        sortBy: sortBy,
        sortAscending:
            ascending ??
            (current.sortBy == sortBy ? !current.sortAscending : false),
      ),
    );
  }

  void setViewMode(MovieViewMode mode) {
    final current = centerState.asData?.value;
    if (current == null) return;
    centerState = AsyncData(current.copyWith(viewMode: mode));
  }

  Future<void> createScrapeTask(MovieVideoItem item) async {
    final current = centerState.asData?.value;
    if (current == null) {
      return;
    }
    try {
      final task = await _api.createScrapeTask(fileNodeId: item.fileNodeId);
      await refresh();
      final refreshed = centerState.asData?.value ?? current;
      centerState = AsyncData(refreshed.copyWith(lastTask: task));
    } on Exception catch (e) {
      _setError(describeUserFacingError(e).message);
      rethrow;
    }
  }

  Future<void> probeItem(MovieVideoItem item) async {
    try {
      await _api.probeItem(item.id);
      await refresh();
    } on Exception catch (e) {
      _setError(describeUserFacingError(e).message);
      rethrow;
    }
  }

  Future<void> createTranscodeTask(MovieVideoItem item) async {
    final current = centerState.asData?.value;
    if (current == null) {
      return;
    }
    try {
      final task = await _api.createTranscodeTask(item.id);
      final tasks = await _api.tasks();
      centerState = AsyncData(current.copyWith(lastTask: task, tasks: tasks));
    } on Exception catch (e) {
      _setError(describeUserFacingError(e).message);
      rethrow;
    }
  }

  Future<void> createAudioExtractTask(MovieVideoItem item) async {
    final current = centerState.asData?.value;
    if (current == null) {
      return;
    }
    try {
      final task = await _api.createTranscodeTask(item.id, audioOnly: true);
      final tasks = await _api.tasks();
      centerState = AsyncData(current.copyWith(lastTask: task, tasks: tasks));
    } on Exception catch (e) {
      _setError(describeUserFacingError(e).message);
      rethrow;
    }
  }

  /// 仅刷新影视任务状态，不重载媒体列表或播放器数据。
  Future<void> refreshTasksForRealtime() async {
    final current = centerState.asData?.value;
    if (current == null) return;
    final tasks = await _api.tasks();
    centerState = AsyncData(current.copyWith(tasks: tasks));
  }

  Future<void> toggleFavorite(
    MovieVideoItem item, {
    bool favorite = true,
  }) async {
    try {
      await _api.favorite(videoItemId: item.id, favorite: favorite);
      await refresh();
    } on Exception catch (e) {
      _setError(describeUserFacingError(e).message);
      rethrow;
    }
  }

  Future<TaskSubmission> deleteItem(
    MovieVideoItem item, {
    bool cascade = false,
  }) async {
    try {
      final submission = await _api.deleteItem(item.id, cascade: cascade);
      await refresh();
      centerRef.invalidate(activeTaskSummaryProvider);
      unawaited(centerRef.read(taskListProvider.notifier).load());
      return submission;
    } on Exception catch (e) {
      _setError(describeUserFacingError(e).message);
      rethrow;
    }
  }

  /// 更新影视条目元数据。
  Future<void> updateMetadata({
    required String videoItemId,
    required String title,
    String? originalTitle,
    DateTime? releaseDate,
    String? overview,
    String? posterFileId,
    String? backdropFileId,
    int? runtimeSeconds,
    String metadataStatus = 'MANUAL',
  }) async {
    try {
      await _api.updateMetadata(
        videoItemId: videoItemId,
        title: title,
        originalTitle: originalTitle,
        releaseDate: releaseDate,
        overview: overview,
        posterFileId: posterFileId,
        backdropFileId: backdropFileId,
        runtimeSeconds: runtimeSeconds,
        metadataStatus: metadataStatus,
      );
      await refresh();
      centerRef.invalidate(movieDetailProvider(videoItemId));
    } on Exception catch (error) {
      _setError(describeUserFacingError(error).message);
      rethrow;
    }
  }

  /// 切换剧集收藏状态。
  Future<void> toggleSeriesFavorite(String seriesId) async {
    try {
      await _api.toggleSeriesFavorite(seriesId);
      await refresh();
    } on Exception catch (error) {
      _setError(describeUserFacingError(error).message);
      rethrow;
    }
  }

  /// 上传并绑定外挂字幕。
  Future<void> uploadSubtitle({
    required String videoItemId,
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    required String language,
  }) async {
    try {
      final session = await _api.createUploadSession(
        fileName: fileName,
        sizeBytes: bytes.length,
        mimeType: mimeType,
      );
      final uploadUrl = session.uploadUrl;
      if (uploadUrl != null && uploadUrl.isNotEmpty) {
        await _api.uploadToPresignedUrl(
          presignedUrl: uploadUrl,
          bytes: bytes,
          mimeType: mimeType,
        );
      }
      final fileNode = await _api.completeUploadSession(
        uploadId: session.uploadId,
      );
      await _api.uploadSubtitle(
        videoItemId: videoItemId,
        fileNodeId: fileNode.id,
        language: language,
        label: fileName,
      );
      centerRef.invalidate(movieSubtitlesProvider(videoItemId));
    } on Exception catch (error) {
      _setError(describeUserFacingError(error).message);
      rethrow;
    }
  }

  /// 删除外挂字幕。
  Future<void> deleteSubtitle({
    required String videoItemId,
    required String subtitleId,
  }) async {
    try {
      await _api.deleteSubtitle(subtitleId);
      centerRef.invalidate(movieSubtitlesProvider(videoItemId));
    } on Exception catch (error) {
      _setError(describeUserFacingError(error).message);
      rethrow;
    }
  }

  Future<void> deleteHistoryItem(MovieWatchHistory entry) async {
    try {
      await _api.deleteHistoryItem(entry.id);
      await refresh();
    } on Exception catch (e) {
      _setError(describeUserFacingError(e).message);
      rethrow;
    }
  }

  Future<void> clearHistory() async {
    try {
      await _api.clearHistory();
      await refresh();
    } on Exception catch (e) {
      _setError(describeUserFacingError(e).message);
      rethrow;
    }
  }

  Future<void> createCollection({
    required String name,
    String? description,
    String? coverFileId,
  }) async {
    await _api.createCollection(
      name: name,
      description: description,
      coverFileId: coverFileId,
    );
    await refresh();
  }

  Future<List<MovieVideoItem>> collectionItems(String collectionId) async {
    return _api.collectionItems(collectionId);
  }

  /// 拉取合集添加选择器的电影候选列表（最近更新前 100 部）。
  ///
  /// 剧集/动漫为系列实体，后端合集条目仅支持视频条目，故只返回电影。
  Future<List<MovieVideoItem>> loadMovieCandidates() async {
    final page = await _api.libraryPage(mediaType: 'MOVIE', page: 0, size: 100);
    return page.items.where((item) => item.mediaType == 'MOVIE').toList();
  }

  /// 收藏分区同时拉取影片收藏与系列（剧集/动漫）收藏。
  Future<List<Object>> _loadFavoriteLists() async {
    final favorites = await Future.wait([
      _api.favorites(),
      _api.favoriteSeries(),
    ]);
    return [favorites[0], favorites[1]];
  }

  /// 更新系列（剧集/动漫）标题与简介。
  Future<void> updateSeriesMetadata({
    required String seriesId,
    required String title,
    String? overview,
  }) async {
    try {
      await _api.updateSeriesMetadata(
        seriesId: seriesId,
        title: title,
        overview: overview,
      );
      await refresh();
      centerRef.invalidate(movieSeriesDetailProvider(seriesId));
    } on Exception catch (error) {
      _setError(describeUserFacingError(error).message);
      rethrow;
    }
  }

  Future<void> addCollectionItem({
    required String collectionId,
    required String videoItemId,
  }) async {
    try {
      await _api.addCollectionItem(
        collectionId: collectionId,
        videoItemId: videoItemId,
      );
      await refresh();
      centerRef.invalidate(collectionItemsProvider(collectionId));
    } on Exception catch (e) {
      _setError(describeUserFacingError(e).message);
      rethrow;
    }
  }

  Future<void> removeCollectionItem({
    required String collectionId,
    required String videoItemId,
  }) async {
    try {
      await _api.removeCollectionItem(
        collectionId: collectionId,
        videoItemId: videoItemId,
      );
      await refresh();
      centerRef.invalidate(collectionItemsProvider(collectionId));
    } on Exception catch (e) {
      _setError(describeUserFacingError(e).message);
      rethrow;
    }
  }

  Future<void> deleteCollection(String collectionId) async {
    try {
      await _api.deleteCollection(collectionId);
      await refresh();
    } on Exception catch (e) {
      _setError(describeUserFacingError(e).message);
      rethrow;
    }
  }
}
