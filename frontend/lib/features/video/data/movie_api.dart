import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:omninest/core/config/file_size_thresholds.dart';
import 'package:omninest/core/device/playback_device_identity.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/features/video/domain/movie_models.dart';
import 'package:omninest/features/tasks/domain/task_record.dart';

class MovieApi {
  const MovieApi(this.apiClient);

  static const int _subtitleMaxBytes = FileSizeThresholds.subtitleMaxBytes;

  final ApiClient apiClient;

  Future<MovieDashboard> dashboard() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/dashboard',
    );
    return MovieDashboard.fromJson(
      _resolveDashboardJson(parseData(response.data)),
    );
  }

  Future<MediaPage<MovieVideoItem>> libraryPage({
    String mediaType = 'MOVIE',
    String? metadataStatus,
    int page = 0,
    int size = 36,
    String sort = 'updatedAt,desc',
  }) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/library/page',
      queryParameters: {
        'mediaType': mediaType,
        if (metadataStatus != null) 'metadataStatus': metadataStatus,
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

  Future<List<MovieContinueWatching>> continueWatching() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/continue',
    );
    return parseList(response.data)
        .map((json) => MovieContinueWatching.fromJson(_resolvePosterJson(json)))
        .toList();
  }

  Future<List<MovieVideoItem>> favorites() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/favorites',
    );
    return parseList(response.data).map(_videoItemFromJson).toList();
  }

  Future<List<MovieSeries>> favoriteSeries() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/favorites/series',
    );
    return parseList(response.data).map(_seriesFromJson).toList();
  }

  Future<MovieSeries> updateSeriesMetadata({
    required String seriesId,
    required String title,
    String? overview,
  }) async {
    final response = await apiClient.dio.put<Map<String, dynamic>>(
      '/admin/video/series/$seriesId/metadata',
      data: {'title': title, 'overview': overview},
    );
    return _seriesFromJson(parseData(response.data));
  }

  Future<List<MovieWatchHistory>> history() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/history',
    );
    return parseList(response.data)
        .map((json) => MovieWatchHistory.fromJson(_resolvePosterJson(json)))
        .toList();
  }

  Future<void> deleteHistoryItem(String historyId) async {
    await apiClient.dio.delete<Map<String, dynamic>>(
      '/video/history/$historyId',
    );
  }

  Future<void> clearHistory() async {
    await apiClient.dio.delete<Map<String, dynamic>>('/video/history');
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
    String metadataStatus = 'MANUAL',
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
        'metadataStatus': metadataStatus,
      },
    );
    return _videoItemFromJson(parseData(response.data));
  }

  Future<PlaybackPlan> playbackPlan(String videoItemId) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/items/$videoItemId/playback',
    );
    return PlaybackPlan.fromJson(parseData(response.data));
  }

  Future<PlaybackPlan> updateProgress({
    required String videoItemId,
    required int positionSeconds,
    required int durationSeconds,
    bool completed = false,
  }) async {
    final deviceId = await PlaybackDeviceIdentity.getOrCreate();
    final response = await apiClient.dio.put<Map<String, dynamic>>(
      '/video/items/$videoItemId/progress',
      data: {
        'positionSeconds': positionSeconds,
        'durationSeconds': durationSeconds,
        'completed': completed,
        'clientUpdatedAt': DateTime.now().toUtc().toIso8601String(),
        'deviceId': deviceId,
      },
    );
    return PlaybackPlan.fromJson(parseData(response.data));
  }

  /// 读取有界字幕文本。
  Future<String> loadSubtitle(String url) async {
    final response = await apiClient.dio.get<ResponseBody>(
      url,
      options: Options(
        responseType: ResponseType.stream,
        headers: {'Range': 'bytes=0-${_subtitleMaxBytes - 1}'},
        validateStatus: (status) => status == 200 || status == 206,
      ),
    );
    final body = response.data;
    if (body == null) {
      return '';
    }
    final bytes = BytesBuilder(copy: false);
    var remaining = _subtitleMaxBytes;
    await for (final chunk in body.stream) {
      if (remaining <= 0) {
        break;
      }
      if (chunk.length <= remaining) {
        bytes.add(chunk);
        remaining -= chunk.length;
      } else {
        bytes.add(chunk.sublist(0, remaining));
        remaining = 0;
      }
    }
    return utf8.decode(bytes.takeBytes(), allowMalformed: true);
  }

  Future<List<VideoScrapeCandidate>> scrapeCandidates(String fileNodeId) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/scrape/candidates',
      queryParameters: {'fileNodeId': fileNodeId},
    );
    return parseList(response.data).map(VideoScrapeCandidate.fromJson).toList();
  }

  Future<ScrapeTask> createScrapeTask({
    required String fileNodeId,
    bool force = false,
  }) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/video/scrape/tasks',
      data: {'fileNodeId': fileNodeId, 'force': force},
    );
    return ScrapeTask.fromJson(parseData(response.data));
  }

  Future<void> probeItem(String videoItemId) async {
    await apiClient.dio.post<Map<String, dynamic>>(
      '/video/items/$videoItemId/probe',
    );
  }

  Future<MovieFavoriteState> favorite({
    required String videoItemId,
    required bool favorite,
  }) async {
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
    await apiClient.dio.post<Map<String, dynamic>>(
      '/video/collections/$collectionId/items',
      data: {'videoItemId': videoItemId},
    );
  }

  Future<void> removeCollectionItem({
    required String collectionId,
    required String videoItemId,
  }) async {
    await apiClient.dio.delete<Map<String, dynamic>>(
      '/video/collections/$collectionId/items/$videoItemId',
    );
  }

  Future<void> deleteCollection(String collectionId) async {
    await apiClient.dio.delete<Map<String, dynamic>>(
      '/video/collections/$collectionId',
    );
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
      '/video/library-sources/$sourceId/access',
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
      '/video/library-sources/$sourceId/access',
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
      '/storage/locations/$locationId/directories',
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
      '/admin/storage/mounts/$mountKey/directories',
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
      '/video/library-sources/$sourceId',
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
    await apiClient.dio.delete<Map<String, dynamic>>(
      '/video/library-sources/$sourceId',
    );
  }

  Future<ScrapeTask> scanLibrarySource(String sourceId) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/video/library-sources/$sourceId/scan/tasks',
    );
    return ScrapeTask.fromJson(parseData(response.data));
  }

  Future<ScrapeTask> discoverLibrarySource(String sourceId) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/video/library-sources/$sourceId/discovery/tasks',
    );
    return ScrapeTask.fromJson(parseData(response.data));
  }

  Future<MediaScanRun?> latestMediaScanRun(String sourceId) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/library-sources/$sourceId/scan-runs/latest',
    );
    final data = parseEnvelope(response.data)['data'];
    return data is Map<String, dynamic> ? MediaScanRun.fromJson(data) : null;
  }

  Future<MediaScanRun> mediaScanRun(String runId) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/scan-runs/$runId',
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
      '/video/scan-runs/$runId/tree',
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
      '/video/scan-runs/$runId/selection-rules',
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
      '/video/scan-runs/$runId/selection-summary',
    );
    return MediaSelectionSummary.fromJson(parseData(response.data));
  }

  Future<ScrapeTask> applyMediaSelection({
    required String runId,
    required int expectedRevision,
  }) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/video/scan-runs/$runId/apply/tasks',
      data: {'expectedRevision': expectedRevision},
    );
    return ScrapeTask.fromJson(parseData(response.data));
  }

  Future<MediaScanRun> pauseMediaScanRun(String runId) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/video/scan-runs/$runId/pause',
    );
    return MediaScanRun.fromJson(parseData(response.data));
  }

  Future<MediaScanRun> cancelMediaScanRun(String runId) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/video/scan-runs/$runId/cancel',
    );
    return MediaScanRun.fromJson(parseData(response.data));
  }

  Future<NfoExport> nfoPreview(String videoItemId) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/items/$videoItemId/nfo',
    );
    return NfoExport.fromJson(parseData(response.data));
  }

  Future<NfoExport> exportNfo(String videoItemId) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/video/items/$videoItemId/nfo',
    );
    return NfoExport.fromJson(parseData(response.data));
  }

  Future<List<MovieSeries>> seriesByType({String seriesType = 'TV'}) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/series/by-type',
      queryParameters: {'seriesType': seriesType},
    );
    return parseList(response.data).map(_seriesFromJson).toList();
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

  Future<void> toggleSeriesFavorite(String seriesId) async {
    await apiClient.dio.post<Map<String, dynamic>>(
      '/video/series/$seriesId/favorite',
    );
  }

  Future<List<SubtitleTrack>> listSubtitles(String videoItemId) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/items/$videoItemId/subtitles',
    );
    return parseList(response.data).map(SubtitleTrack.fromJson).toList();
  }

  Future<SubtitleTrack> uploadSubtitle({
    required String videoItemId,
    required String fileNodeId,
    required String language,
    required String label,
    String kind = 'SUBTITLE',
  }) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/video/items/$videoItemId/subtitles',
      data: {
        'fileNodeId': fileNodeId,
        'language': language,
        'label': label,
        'kind': kind,
      },
    );
    return SubtitleTrack.fromJson(parseData(response.data));
  }

  Future<SubtitleTrack> updateSubtitle({
    required String subtitleId,
    String? language,
    String? label,
    String? kind,
  }) async {
    final response = await apiClient.dio.put<Map<String, dynamic>>(
      '/video/subtitles/$subtitleId',
      data: {
        if (language != null) 'language': language,
        if (label != null) 'label': label,
        if (kind != null) 'kind': kind,
      },
    );
    return SubtitleTrack.fromJson(parseData(response.data));
  }

  Future<void> deleteSubtitle(String subtitleId) async {
    await apiClient.dio.delete<Map<String, dynamic>>(
      '/video/subtitles/$subtitleId',
    );
  }

  Future<UploadSession> createUploadSession({
    required String fileName,
    required int sizeBytes,
    String? mimeType,
  }) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/uploads/sessions',
      data: {
        'fileName': fileName,
        'sizeBytes': sizeBytes,
        if (mimeType != null) 'mimeType': mimeType,
      },
    );
    return UploadSession.fromJson(parseData(response.data));
  }

  Future<void> uploadToPresignedUrl({
    required String presignedUrl,
    required Uint8List bytes,
    String? mimeType,
  }) async {
    final dio = Dio();
    await dio.put<void>(
      presignedUrl,
      data: bytes,
      options: Options(
        headers: {
          if (mimeType != null) 'Content-Type': mimeType,
          'Content-Length': bytes.length,
        },
      ),
    );
  }

  Future<FileNodeResult> completeUploadSession({
    required String uploadId,
  }) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/uploads/$uploadId/complete',
    );
    return FileNodeResult.fromJson(parseData(response.data));
  }

  Map<String, dynamic> parseData(Map<String, dynamic>? body) {
    final envelope = parseEnvelope(body);
    final data = envelope['data'];
    if (data is! Map<String, dynamic>) {
      throw const AppException(code: 'INVALID_RESPONSE', message: '影视响应格式不正确');
    }
    return data;
  }

  List<Map<String, dynamic>> parseList(Map<String, dynamic>? body) {
    final data = parseEnvelope(body)['data'];
    if (data is! List) {
      throw const AppException(code: 'INVALID_RESPONSE', message: '影视列表格式不正确');
    }
    return data.whereType<Map<String, dynamic>>().toList();
  }

  Map<String, dynamic> parseEnvelope(Map<String, dynamic>? body) {
    if (body == null) {
      throw const AppException(code: 'EMPTY_RESPONSE', message: '服务端没有返回影视结果');
    }
    final code = body['code'];
    if (code != 200) {
      throw AppException(
        code: code?.toString() ?? 'MOVIE_ERROR',
        message: body['message']?.toString() ?? '影视操作失败',
      );
    }
    return body;
  }

  // ---- 相对资源 URL 解析 ----
  // 后端对本地媒体库等场景返回相对路径（/api/v1/...），Flutter 的 Image.network /
  // CachedNetworkImage 需要绝对地址，这里在 data 层统一解析为 API origin。

  String? _resolveApiUrl(String? url) {
    if (url == null || url.isEmpty) return url;
    final parsed = Uri.tryParse(url);
    if (parsed != null && parsed.hasScheme) return url;
    if (!url.startsWith('/')) return url;
    final baseUri = Uri.parse(apiClient.dio.options.baseUrl);
    final origin = '${baseUri.scheme}://${baseUri.authority}';
    return '$origin$url';
  }

  /// 演员头像：MinIO 绝对地址直接使用；TMDB 相对头像路径降级拼接 TMDB 图床。
  String? _resolveProfileImageUrl(String? url) {
    if (url == null || url.isEmpty) return url;
    final parsed = Uri.tryParse(url);
    if (parsed != null && parsed.hasScheme) return url;
    if (url.startsWith('/')) {
      return 'https://image.tmdb.org/t/p/w185$url';
    }
    return url;
  }

  /// 影片/剧集条目的媒体字段（poster/backdrop/assets/演员/职员）统一解析。
  Map<String, dynamic> _resolveMediaJson(Map<String, dynamic> json) {
    final resolved = Map<String, dynamic>.from(json);
    resolved['posterUrl'] = _resolveApiUrl(json['posterUrl']?.toString());
    resolved['backdropUrl'] = _resolveApiUrl(json['backdropUrl']?.toString());
    final rawAssets = json['assets'];
    if (rawAssets is Map) {
      resolved['assets'] = rawAssets.map((key, value) {
        if (value is Map) {
          final asset = Map<String, dynamic>.from(value);
          asset['url'] = _resolveApiUrl(asset['url']?.toString());
          return MapEntry(key, asset);
        }
        return MapEntry(key, value);
      });
    }
    resolved['castMembers'] = _resolveMembers(json['castMembers']);
    resolved['crewMembers'] = _resolveMembers(json['crewMembers']);
    return resolved;
  }

  List<dynamic>? _resolveMembers(Object? raw) {
    if (raw is! List) return null;
    return raw.map((member) {
      if (member is Map) {
        final resolved = Map<String, dynamic>.from(member);
        resolved['profilePath'] = _resolveProfileImageUrl(
          resolved['profilePath']?.toString(),
        );
        return resolved;
      }
      return member;
    }).toList();
  }

  /// 仅含 posterUrl 的条目（继续观看、观看历史、季）。
  Map<String, dynamic> _resolvePosterJson(Map<String, dynamic> json) {
    final resolved = Map<String, dynamic>.from(json);
    resolved['posterUrl'] = _resolveApiUrl(json['posterUrl']?.toString());
    return resolved;
  }

  Map<String, dynamic> _resolveAssetJson(Map<String, dynamic> json) {
    final resolved = Map<String, dynamic>.from(json);
    resolved['url'] = _resolveApiUrl(json['url']?.toString());
    return resolved;
  }

  Map<String, dynamic> _resolveSeriesDetailJson(Map<String, dynamic> json) {
    final resolved = Map<String, dynamic>.from(json);
    final series = json['series'];
    if (series is Map) {
      resolved['series'] = _resolveMediaJson(Map<String, dynamic>.from(series));
    }
    resolved['cast'] = _resolveMembers(json['cast']);
    resolved['crew'] = _resolveMembers(json['crew']);
    final seasons = json['seasons'];
    if (seasons is List) {
      resolved['seasons'] =
          seasons.map((season) {
            if (season is Map) {
              return _resolvePosterJson(Map<String, dynamic>.from(season));
            }
            return season;
          }).toList();
    }
    return resolved;
  }

  Map<String, dynamic> _resolveSeasonDetailJson(Map<String, dynamic> json) {
    final resolved = Map<String, dynamic>.from(json);
    final season = json['season'];
    if (season is Map) {
      resolved['season'] = _resolvePosterJson(
        Map<String, dynamic>.from(season),
      );
    }
    final episodes = json['episodes'];
    if (episodes is List) {
      resolved['episodes'] =
          episodes.map((episode) {
            if (episode is Map) {
              return _resolveMediaJson(Map<String, dynamic>.from(episode));
            }
            return episode;
          }).toList();
    }
    return resolved;
  }

  MovieVideoItem _videoItemFromJson(Map<String, dynamic> json) =>
      MovieVideoItem.fromJson(_resolveMediaJson(json));

  MovieSeries _seriesFromJson(Map<String, dynamic> json) =>
      MovieSeries.fromJson(_resolveMediaJson(json));

  /// 首页摘要内部嵌有影片、继续观看与系列列表，需要一并解析媒体 URL。
  Map<String, dynamic> _resolveDashboardJson(Map<String, dynamic> json) {
    final resolved = Map<String, dynamic>.from(json);
    final recentlyAdded = json['recentlyAdded'];
    if (recentlyAdded is List) {
      resolved['recentlyAdded'] =
          recentlyAdded.map((item) {
            if (item is Map) {
              return _resolveMediaJson(Map<String, dynamic>.from(item));
            }
            return item;
          }).toList();
    }
    final continueWatching = json['continueWatching'];
    if (continueWatching is List) {
      resolved['continueWatching'] =
          continueWatching.map((item) {
            if (item is Map) {
              return _resolvePosterJson(Map<String, dynamic>.from(item));
            }
            return item;
          }).toList();
    }
    final series = json['series'];
    if (series is List) {
      resolved['series'] =
          series.map((item) {
            if (item is Map) {
              return _resolveMediaJson(Map<String, dynamic>.from(item));
            }
            return item;
          }).toList();
    }
    return resolved;
  }
}
