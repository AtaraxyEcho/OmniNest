part of 'movie_api.dart';

/// 目录、收藏与详情读取。
mixin MovieApiCatalog on MovieApiBase {
  Future<MovieDashboard> dashboard() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/dashboard',
    );
    return MovieDashboard.fromJson(
      _resolveDashboardJson(parseData(response.data)),
    );
  }

  /// 分页获取视频库。
  ///
  /// [keyword] 为标题关键词，检索在数据侧覆盖全库；空白等同不传。
  Future<MediaPage<MovieVideoItem>> libraryPage({
    String mediaType = 'MOVIE',
    String? metadataStatus,
    String? keyword,
    int page = 0,
    int size = 36,
    String sort = 'updatedAt,desc',
  }) async {
    final trimmedKeyword = keyword?.trim();
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/library/page',
      queryParameters: {
        'mediaType': mediaType,
        if (metadataStatus != null) 'metadataStatus': metadataStatus,
        if (trimmedKeyword != null && trimmedKeyword.isNotEmpty)
          'q': trimmedKeyword,
        'page': page,
        'size': size,
        'sort': sort,
      },
    );
    return MediaPage.fromJson(parseData(response.data), _videoItemFromJson);
  }

  Future<List<MovieVideoItem>> recent({int days = 30}) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/recent',
      queryParameters: {'days': days},
    );
    return parseList(response.data).map(_videoItemFromJson).toList();
  }

  Future<List<MovieVideoItem>> seriesEpisodes(String seriesId) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/series/$seriesId/episodes',
    );
    return parseList(response.data).map(_videoItemFromJson).toList();
  }

  Future<List<MovieVideoItem>> favorites() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/favorites',
    );
    return parseList(response.data).map(_videoItemFromJson).toList();
  }

  /// 分页获取收藏视频：滚动加载消费，按收藏时间倒序。
  Future<MediaPage<MovieVideoItem>> favoritesPage({
    int page = 0,
    int size = 50,
  }) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/favorites/page',
      queryParameters: {'page': page, 'size': size},
    );
    return MediaPage.fromJson(parseData(response.data), _videoItemFromJson);
  }

  Future<List<MovieSeries>> favoriteSeries() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/favorites/series',
    );
    return parseList(response.data).map(_seriesFromJson).toList();
  }

  /// 分页获取收藏系列：滚动加载消费，按收藏时间倒序。
  Future<MediaPage<MovieSeries>> favoriteSeriesPage({
    int page = 0,
    int size = 50,
  }) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/favorites/series/page',
      queryParameters: {'page': page, 'size': size},
    );
    return MediaPage.fromJson(parseData(response.data), _seriesFromJson);
  }

  Future<MovieSeries> updateSeriesMetadata({
    required String seriesId,
    required String title,
    String? overview,
    String? seriesType,
    DateTime? firstAirDate,
    double? rating,
    List<String>? genres,
    List<String>? cast,
    String? runtime,
    String? posterUrl,
    String? posterFileId,
    bool clearPoster = false,
    bool restoreOriginal = false,
  }) async {
    final response = await apiClient.dio.put<Map<String, dynamic>>(
      '/admin/video/series/$seriesId/metadata',
      data: {
        'title': title,
        'overview': overview,
        'seriesType': seriesType,
        'firstAirDate':
            firstAirDate == null
                ? null
                : '${firstAirDate.year.toString().padLeft(4, '0')}-'
                    '${firstAirDate.month.toString().padLeft(2, '0')}-'
                    '${firstAirDate.day.toString().padLeft(2, '0')}',
        'rating': rating,
        'genres': genres,
        'cast': cast,
        'runtime': runtime,
        'posterUrl': posterUrl,
        'posterFileId': posterFileId,
        if (clearPoster) 'clearPoster': true,
        if (restoreOriginal) 'restoreOriginal': true,
      }..removeWhere((_, value) => value == null),
    );
    return _seriesFromJson(parseData(response.data));
  }

  /// 上传本地影视海报，返回派生资产文件节点 ID。
  Future<String> uploadPoster({
    required List<int> bytes,
    required String fileName,
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: fileName),
    });
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/video/posters',
      data: formData,
    );
    final data = parseData(response.data);
    return data['fileNodeId'] as String;
  }

  Future<List<MovieCollection>> collections() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/collections',
    );
    return parseList(response.data).map(MovieCollection.fromJson).toList();
  }

  Future<List<MovieTask>> tasks({String? type}) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/tasks',
      queryParameters: {if (type != null) 'type': type},
    );
    return parseList(response.data).map(MovieTask.fromJson).toList();
  }

  Future<MovieVideoItem> detail(String videoItemId) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/items/$videoItemId',
    );
    return _videoItemFromJson(parseData(response.data));
  }

  Future<List<MovieVideoItem>> versions(String videoItemId) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/items/$videoItemId/versions',
    );
    return parseList(response.data).map(_videoItemFromJson).toList();
  }

  Future<MovieFiles> files(String videoItemId) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/items/$videoItemId/files',
    );
    return MovieFiles.fromJson(parseData(response.data));
  }

  Future<TaskSubmission> deleteItem(
    String videoItemId, {
    bool cascade = false,
  }) async {
    final response = await apiClient.dio.delete<Map<String, dynamic>>(
      '/video/items/$videoItemId',
      queryParameters: {'cascade': cascade},
    );
    return TaskSubmission.fromJson(parseData(response.data));
  }

  Future<MovieVideoItem> updateMetadata({
    required String videoItemId,
    required String title,
    String? originalTitle,
    DateTime? releaseDate,
    String? overview,
    String? posterFileId,
    String? backdropFileId,
    int? runtimeSeconds,
    List<String>? genres,
    double? rating,
    List<String>? cast,
    String? posterUrl,
    String metadataStatus = 'MANUAL',
    bool restoreOriginal = false,
    bool clearRuntime = false,
    bool clearPoster = false,
  }) async {
    final response = await apiClient.dio.put<Map<String, dynamic>>(
      '/admin/video/items/$videoItemId/metadata',
      data: {
        'title': title,
        'originalTitle': originalTitle,
        'releaseDate': releaseDate?.toIso8601String().split('T').first,
        'overview': overview,
        'posterFileId': posterFileId,
        'backdropFileId': backdropFileId,
        'runtimeSeconds': runtimeSeconds,
        'genres': genres,
        'rating': rating,
        'cast': cast,
        'posterUrl': posterUrl,
        'metadataStatus': metadataStatus,
        'restoreOriginal': restoreOriginal,
        'clearRuntime': clearRuntime,
        'clearPoster': clearPoster,
      },
    );
    return _videoItemFromJson(parseData(response.data));
  }

  Future<List<VideoScrapeCandidate>> scrapeCandidates(String fileNodeId) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/scrape/candidates',
      queryParameters: {'fileNodeId': fileNodeId},
      // 候选接口是幂等只读请求，5xx/超时重试会把 25s 预算放大成 ~75s；后端已在 18s 内返回结构化错误。
      options: Options(
        receiveTimeout: const Duration(seconds: 25),
        extra: const {skipServerErrorRetryKey: true},
      ),
    );
    return parseList(response.data).map(VideoScrapeCandidate.fromJson).toList();
  }

  /// 创建刮削任务；传入 [provider] 与 [externalId] 时按用户选中的候选刮削。
  Future<ScrapeTask> createScrapeTask({
    required String fileNodeId,
    bool force = false,
    String? provider,
    String? externalId,
  }) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/video/scrape/tasks',
      data: {
        'fileNodeId': fileNodeId,
        'force': force,
        if (provider != null && provider.isNotEmpty) 'provider': provider,
        if (externalId != null && externalId.isNotEmpty)
          'externalId': externalId,
      },
    );
    return ScrapeTask.fromJson(parseData(response.data));
  }

  Future<void> probeItem(String videoItemId) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/video/items/$videoItemId/probe',
    );
    ensureEnvelopeSuccess(response.data, fallbackMessage: '探测视频信息失败');
  }

  /// 收藏 / 取消收藏（用户主动写）：无能力时抛 FORBIDDEN，禁止假成功。
  Future<MovieFavoriteState> favorite({
    required String videoItemId,
    required bool favorite,
  }) async {
    apiClient.requirePermission(activityWritePermission);
    final response = await apiClient.dio.put<Map<String, dynamic>>(
      '/video/items/$videoItemId/favorite',
      queryParameters: {'favorite': favorite},
    );
    return MovieFavoriteState.fromJson(parseData(response.data));
  }

  Future<MovieFavoriteState> favoriteStatus(String videoItemId) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/items/$videoItemId/favorite/status',
    );
    return MovieFavoriteState.fromJson(parseData(response.data));
  }

  Future<List<MovieVideoItem>> watchlistItems() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/watchlist',
    );
    return parseList(response.data).map(_videoItemFromJson).toList();
  }

  Future<MovieWatchlistState> watchlistStatus(String videoItemId) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/items/$videoItemId/watchlist/status',
    );
    return MovieWatchlistState.fromJson(parseData(response.data));
  }

  Future<MovieWatchlistState> setWatchlist({
    required String videoItemId,
    required bool watchlisted,
  }) async {
    apiClient.requirePermission(activityWritePermission);
    final response = await apiClient.dio.put<Map<String, dynamic>>(
      '/video/items/$videoItemId/watchlist',
      queryParameters: {'watchlisted': watchlisted},
    );
    return MovieWatchlistState.fromJson(parseData(response.data));
  }

  Future<MovieCollection> createCollection({
    required String name,
    String? description,
    String? coverFileId,
  }) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/video/collections',
      data: {
        'name': name,
        'description': description,
        'coverFileId': coverFileId,
      },
    );
    return MovieCollection.fromJson(parseData(response.data));
  }

  Future<List<MovieVideoItem>> collectionItems(String collectionId) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/collections/$collectionId/items',
    );
    return parseList(response.data).map(_videoItemFromJson).toList();
  }

  Future<void> addCollectionItem({
    required String collectionId,
    required String videoItemId,
  }) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/video/collections/$collectionId/items',
      data: {'videoItemId': videoItemId},
    );
    ensureEnvelopeSuccess(response.data, fallbackMessage: '添加到合集失败');
  }

  Future<void> removeCollectionItem({
    required String collectionId,
    required String videoItemId,
  }) async {
    final response = await apiClient.dio.delete<Map<String, dynamic>>(
      '/video/collections/$collectionId/items/$videoItemId',
    );
    ensureEnvelopeSuccess(response.data, fallbackMessage: '从合集移除失败');
  }

  Future<void> deleteCollection(String collectionId) async {
    final response = await apiClient.dio.delete<Map<String, dynamic>>(
      '/video/collections/$collectionId',
    );
    ensureEnvelopeSuccess(response.data, fallbackMessage: '删除合集失败');
  }

  Future<ScrapeTask> createTranscodeTask(
    String videoItemId, {
    bool audioOnly = false,
  }) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/video/items/$videoItemId/transcode/tasks',
      queryParameters: {'audioOnly': audioOnly},
    );
    return ScrapeTask.fromJson(parseData(response.data));
  }

  Future<ScrapeTask> scanLibrary({
    String? rootFolderId,
    bool incremental = true,
  }) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/video/scan/tasks',
      data: {'rootFolderId': rootFolderId, 'incremental': incremental},
    );
    return ScrapeTask.fromJson(parseData(response.data));
  }

  Future<List<MovieSeries>> seriesByType({String seriesType = 'TV'}) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/series/by-type',
      queryParameters: {'seriesType': seriesType},
    );
    return parseList(response.data).map(_seriesFromJson).toList();
  }

  /// 按类型分页获取系列：滚动加载与全库关键词检索共用，按更新时间倒序。
  Future<MediaPage<MovieSeries>> seriesByTypePage({
    String seriesType = 'TV',
    String? keyword,
    int page = 0,
    int size = 50,
  }) async {
    final trimmedKeyword = keyword?.trim();
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/series/by-type/page',
      queryParameters: {
        'seriesType': seriesType,
        if (trimmedKeyword != null && trimmedKeyword.isNotEmpty)
          'q': trimmedKeyword,
        'page': page,
        'size': size,
      },
    );
    return MediaPage.fromJson(parseData(response.data), _seriesFromJson);
  }

  Future<MovieSeriesDetail> seriesDetail(String seriesId) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/series/$seriesId',
    );
    return MovieSeriesDetail.fromJson(
      _resolveSeriesDetailJson(parseData(response.data)),
    );
  }

  Future<MovieSeasonDetail> seasonDetail(
    String seriesId,
    int seasonNumber,
  ) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/series/$seriesId/seasons/$seasonNumber',
    );
    return MovieSeasonDetail.fromJson(
      _resolveSeasonDetailJson(parseData(response.data)),
    );
  }

  Future<List<MovieContentAsset>> itemAssets(String itemId) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/items/$itemId/assets',
    );
    return parseList(response.data)
        .map((json) => MovieContentAsset.fromJson(_resolveAssetJson(json)))
        .toList();
  }

  Future<bool> seriesFavoriteStatus(String seriesId) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/series/$seriesId/favorite/status',
    );
    final data = parseData(response.data);
    return data['favorite'] == true;
  }

  /// 幂等设定剧集收藏（用户主动写）：无能力时抛 FORBIDDEN。
  ///
  /// 目标状态显式传入，弱网重传不会把"收藏"翻成"取消收藏"。
  Future<void> setSeriesFavorite(
    String seriesId, {
    required bool favorite,
  }) async {
    apiClient.requirePermission(activityWritePermission);
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/video/series/$seriesId/favorite',
      queryParameters: {'favorite': favorite},
    );
    ensureEnvelopeSuccess(response.data, fallbackMessage: '收藏剧集失败');
  }

  Future<List<VideoScrapeCandidate>> seriesScrapeCandidates(
    String seriesId,
  ) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/series/${Uri.encodeComponent(seriesId)}/scrape/candidates',
      options: Options(
        receiveTimeout: const Duration(seconds: 25),
        extra: const {skipServerErrorRetryKey: true},
      ),
    );
    return parseList(response.data).map(VideoScrapeCandidate.fromJson).toList();
  }

  Future<ScrapeTask> createSeriesScrapeTask({
    required String seriesId,
    bool force = false,
    String? provider,
    String? externalId,
  }) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/video/series/${Uri.encodeComponent(seriesId)}/scrape/tasks',
      data: {
        'force': force,
        if (provider != null && provider.isNotEmpty) 'provider': provider,
        if (externalId != null && externalId.isNotEmpty)
          'externalId': externalId,
      },
    );
    return ScrapeTask.fromJson(parseData(response.data));
  }

  Future<void> probeSeries(String seriesId) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/video/series/${Uri.encodeComponent(seriesId)}/probe',
    );
    ensureEnvelopeSuccess(response.data, fallbackMessage: '探测剧集信息失败');
  }

  Future<NfoExport> seriesNfoPreview(String seriesId) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/series/${Uri.encodeComponent(seriesId)}/nfo',
    );
    return NfoExport.fromJson(parseData(response.data));
  }

  Future<NfoExport> exportSeriesNfo(
    String seriesId, {
    bool includeEpisodes = false,
  }) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/video/series/${Uri.encodeComponent(seriesId)}/nfo',
      queryParameters: {if (includeEpisodes) 'includeEpisodes': true},
    );
    return NfoExport.fromJson(parseData(response.data));
  }
}
