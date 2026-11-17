part of 'movie_api.dart';

/// 影视库来源、挂载与扫描运行。
mixin MovieApiLibrary on MovieApiBase {
  Future<List<VideoStorageLocation>> accessibleStorageLocations() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/storage/locations/accessible',
    );
    return parseList(response.data).map(VideoStorageLocation.fromJson).toList();
  }

  Future<List<VideoLibrarySource>> librarySources() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/library-sources',
    );
    return parseList(response.data).map(VideoLibrarySource.fromJson).toList();
  }

  Future<MediaLibraryAccessSettings> libraryAccess(String sourceId) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/library-sources/${Uri.encodeComponent(sourceId)}/access',
    );
    return MediaLibraryAccessSettings.fromJson(parseData(response.data));
  }

  Future<MediaLibraryAccessSettings> updateLibraryAccess({
    required String sourceId,
    required MediaLibraryVisibility visibility,
    required Set<String> userIds,
    required int expectedVersion,
  }) async {
    final response = await apiClient.dio.put<Map<String, dynamic>>(
      '/video/library-sources/${Uri.encodeComponent(sourceId)}/access',
      data: {
        'visibilityType': visibility.apiValue,
        'userIds': userIds.toList()..sort(),
        'expectedVersion': expectedVersion,
      },
    );
    return MediaLibraryAccessSettings.fromJson(parseData(response.data));
  }

  Future<MediaPage<MediaLibraryUserCandidate>> libraryAccessUsers({
    String? query,
    int page = 0,
    int size = 50,
  }) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/library-access/users',
      queryParameters: {
        if (query != null && query.trim().isNotEmpty) 'query': query.trim(),
        'page': page,
        'size': size,
      },
    );
    return MediaPage.fromJson(
      parseData(response.data),
      MediaLibraryUserCandidate.fromJson,
    );
  }

  Future<MediaPage<VideoStorageDirectory>> storageDirectories({
    required String locationId,
    String? parent,
    int page = 0,
    int size = 100,
  }) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/storage/locations/${Uri.encodeComponent(locationId)}/directories',
      queryParameters: {
        if (parent != null) 'parent': parent,
        'page': page,
        'size': size,
      },
    );
    return MediaPage.fromJson(
      parseData(response.data),
      VideoStorageDirectory.fromJson,
    );
  }

  Future<List<VideoTrustedMount>> trustedMounts() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/admin/storage/mounts',
    );
    final data = parseEnvelope(response.data)['data'];
    return data is List
        ? data
            .whereType<Map<String, dynamic>>()
            .map(VideoTrustedMount.fromJson)
            .toList()
        : <VideoTrustedMount>[];
  }

  Future<MediaPage<VideoStorageDirectory>> trustedMountDirectories({
    required String mountKey,
    String? parent,
    int page = 0,
    int size = 100,
  }) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/admin/storage/mounts/${Uri.encodeComponent(mountKey)}/directories',
      queryParameters: {
        if (parent != null) 'parent': parent,
        'page': page,
        'size': size,
      },
    );
    return MediaPage.fromJson(
      parseData(response.data),
      VideoStorageDirectory.fromJson,
    );
  }

  Future<List<VideoLibrarySource>> provisionMountLibrary({
    required String mountKey,
    required bool enabled,
    required bool autoImport,
  }) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/video/library-sources/mount-provision',
      data: {
        'mountKey': mountKey,
        'enabled': enabled,
        'autoImport': autoImport,
      },
    );
    final data = parseData(response.data);
    final rawSources = data['sources'];
    return rawSources is List
        ? rawSources
            .whereType<Map<String, dynamic>>()
            .map(VideoLibrarySource.fromJson)
            .toList()
        : const <VideoLibrarySource>[];
  }

  Future<VideoLibrarySource> createLibrarySource({
    required String name,
    String? storageLocationId,
    String? mountKey,
    required String relativeRoot,
    required VideoLibraryType libraryType,
    bool enabled = true,
  }) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/video/library-sources',
      data: {
        'name': name,
        if (storageLocationId != null) 'storageLocationId': storageLocationId,
        if (mountKey != null) 'mountKey': mountKey,
        'relativeRoot': relativeRoot,
        'libraryType': libraryType.apiValue,
        'importPolicy': 'MANUAL_REVIEW',
        'enabled': enabled,
      },
    );
    return VideoLibrarySource.fromJson(parseData(response.data));
  }

  Future<VideoLibrarySource> updateLibrarySource({
    required String sourceId,
    required String name,
    required String relativeRoot,
    required VideoLibraryType libraryType,
    required bool enabled,
  }) async {
    final response = await apiClient.dio.put<Map<String, dynamic>>(
      '/video/library-sources/${Uri.encodeComponent(sourceId)}',
      data: {
        'name': name,
        'relativeRoot': relativeRoot,
        'libraryType': libraryType.apiValue,
        'importPolicy': 'MANUAL_REVIEW',
        'enabled': enabled,
      },
    );
    return VideoLibrarySource.fromJson(parseData(response.data));
  }

  Future<void> deleteLibrarySource(String sourceId) async {
    final response = await apiClient.dio.delete<Map<String, dynamic>>(
      '/video/library-sources/${Uri.encodeComponent(sourceId)}',
    );
    ensureEnvelopeSuccess(response.data, fallbackMessage: '删除视频库源失败');
  }

  Future<ScrapeTask> scanLibrarySource(String sourceId) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/video/library-sources/${Uri.encodeComponent(sourceId)}/scan/tasks',
    );
    return ScrapeTask.fromJson(parseData(response.data));
  }

  Future<ScrapeTask> discoverLibrarySource(String sourceId) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/video/library-sources/${Uri.encodeComponent(sourceId)}/discovery/tasks',
    );
    return ScrapeTask.fromJson(parseData(response.data));
  }

  Future<MediaScanRun?> latestMediaScanRun(String sourceId) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/library-sources/${Uri.encodeComponent(sourceId)}/scan-runs/latest',
    );
    final data = parseEnvelope(response.data)['data'];
    return data is Map<String, dynamic> ? MediaScanRun.fromJson(data) : null;
  }

  Future<MediaScanRun> mediaScanRun(String runId) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/scan-runs/${Uri.encodeComponent(runId)}',
    );
    return MediaScanRun.fromJson(parseData(response.data));
  }

  Future<MediaPage<MediaScanTreeNode>> mediaScanTree({
    required String runId,
    String? parentNodeId,
    int page = 0,
    int size = 100,
  }) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/scan-runs/${Uri.encodeComponent(runId)}/tree',
      queryParameters: {
        if (parentNodeId != null) 'parentNodeId': parentNodeId,
        'page': page,
        'size': size,
      },
    );
    return MediaPage.fromJson(
      parseData(response.data),
      MediaScanTreeNode.fromJson,
    );
  }

  Future<MediaSelectionSummary> updateMediaSelection({
    required String runId,
    required String nodeId,
    required bool selected,
    required int expectedRevision,
  }) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/video/scan-runs/${Uri.encodeComponent(runId)}/selection-rules',
      data: {
        'nodeId': nodeId,
        'selected': selected,
        'expectedRevision': expectedRevision,
      },
    );
    return MediaSelectionSummary.fromJson(parseData(response.data));
  }

  Future<MediaSelectionSummary> mediaSelectionSummary(String runId) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/scan-runs/${Uri.encodeComponent(runId)}/selection-summary',
    );
    return MediaSelectionSummary.fromJson(parseData(response.data));
  }

  Future<ScrapeTask> applyMediaSelection({
    required String runId,
    required int expectedRevision,
  }) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/video/scan-runs/${Uri.encodeComponent(runId)}/apply/tasks',
      data: {'expectedRevision': expectedRevision},
    );
    return ScrapeTask.fromJson(parseData(response.data));
  }

  Future<MediaScanRun> pauseMediaScanRun(String runId) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/video/scan-runs/${Uri.encodeComponent(runId)}/pause',
    );
    return MediaScanRun.fromJson(parseData(response.data));
  }

  Future<MediaScanRun> cancelMediaScanRun(String runId) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/video/scan-runs/${Uri.encodeComponent(runId)}/cancel',
    );
    return MediaScanRun.fromJson(parseData(response.data));
  }

  Future<NfoExport> nfoPreview(String videoItemId) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/items/${Uri.encodeComponent(videoItemId)}/nfo',
    );
    return NfoExport.fromJson(parseData(response.data));
  }

  Future<NfoExport> exportNfo(String videoItemId) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/video/items/${Uri.encodeComponent(videoItemId)}/nfo',
    );
    return NfoExport.fromJson(parseData(response.data));
  }
}
