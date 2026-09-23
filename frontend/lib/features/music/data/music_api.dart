import 'package:dio/dio.dart';
import 'package:omninest/core/device/playback_device_identity.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/core/network/retry_interceptor.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/tasks/domain/task_record.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';

class MusicApi {
  const MusicApi(this.apiClient);

  final ApiClient apiClient;

  Future<MusicDashboard> dashboard() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/music/dashboard',
    );
    return MusicDashboard.fromJson(parseData(response.data));
  }

  Future<MusicSearchResult> search(String keyword) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/music/search',
      queryParameters: {'q': keyword, 'type': 'all'},
    );
    return MusicSearchResult.fromJson(parseData(response.data));
  }

  Future<MusicPagedResult<MusicTrack>> tracks({
    int page = 0,
    int size = 100,
    String sort = 'title,asc',
  }) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/music/tracks',
      queryParameters: {'page': page, 'size': size, 'sort': sort},
    );
    return _parsePage(response.data, MusicTrack.fromJson, '歌曲列表格式不正确');
  }

  Future<MusicPagedResult<MusicAlbum>> albums({
    int page = 0,
    int size = 100,
    String sort = 'updatedAt,desc',
  }) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/music/albums',
      queryParameters: {'page': page, 'size': size, 'sort': sort},
    );
    return _parsePage(response.data, MusicAlbum.fromJson, '专辑列表格式不正确');
  }

  Future<MusicPagedResult<MusicArtist>> artists({
    int page = 0,
    int size = 100,
    String sort = 'name,asc',
  }) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/music/artists',
      queryParameters: {'page': page, 'size': size, 'sort': sort},
    );
    return _parsePage(response.data, MusicArtist.fromJson, '艺术家列表格式不正确');
  }

  Future<List<MusicTrack>> favorites() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/music/favorites',
    );
    return _parseList(response.data, MusicTrack.fromJson, '收藏歌曲格式不正确');
  }

  Future<List<MusicTrack>> recent() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/music/recent',
    );
    return _parseList(response.data, MusicTrack.fromJson, '最近播放格式不正确');
  }

  Future<List<MusicRecentEntry>> recentItems() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/music/recent-items',
    );
    return _parseList(response.data, MusicRecentEntry.fromJson, '最近播放列表格式不正确');
  }

  Future<MusicPagedResult<MusicPlayHistoryEntry>> playHistory({
    int page = 0,
    int size = 50,
  }) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/music/history',
      queryParameters: {'page': page, 'size': size},
    );
    return _parsePage(
      response.data,
      MusicPlayHistoryEntry.fromJson,
      '播放历史格式不正确',
    );
  }

  Future<List<MusicPlaylist>> playlists() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/music/playlists',
    );
    return _parseList(response.data, MusicPlaylist.fromJson, '歌单列表格式不正确');
  }

  Future<MusicPlaylist> createPlaylist({
    required String name,
    String? description,
    String? coverFileId,
  }) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/music/playlists',
      data: {
        'name': name,
        'description': description,
        if (coverFileId != null) 'coverFileId': coverFileId,
      },
    );
    return MusicPlaylist.fromJson(parseData(response.data));
  }

  Future<MusicPlaylist> updatePlaylist({
    required String playlistId,
    required String name,
    String? description,
    String? coverFileId,
  }) async {
    final response = await apiClient.dio.put<Map<String, dynamic>>(
      '/music/playlists/$playlistId',
      data: {
        'name': name,
        'description': description,
        if (coverFileId != null) 'coverFileId': coverFileId,
      },
    );
    return MusicPlaylist.fromJson(parseData(response.data));
  }

  Future<void> deletePlaylist(String playlistId) async {
    await apiClient.dio.delete<Map<String, dynamic>>(
      '/music/playlists/$playlistId',
    );
  }

  Future<List<MusicTrack>> playlistTracks(String playlistId) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/music/playlists/$playlistId/items',
    );
    return _parseList(response.data, MusicTrack.fromJson, '歌单歌曲格式不正确');
  }

  /// 获取专辑内全部曲目（碟号、音轨号排序）。
  Future<List<MusicTrack>> albumTracks(String albumId) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/music/albums/$albumId/tracks',
    );
    return _parseList(response.data, MusicTrack.fromJson, '专辑歌曲格式不正确');
  }

  /// 获取歌手内全部曲目（专辑名、碟号、音轨号排序）。
  Future<List<MusicTrack>> artistTracks(String artistId) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/music/artists/$artistId/tracks',
    );
    return _parseList(response.data, MusicTrack.fromJson, '歌手歌曲格式不正确');
  }

  Future<MusicPlaylist> addPlaylistItems(
    String playlistId,
    List<String> trackIds,
  ) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/music/playlists/$playlistId/items',
      data: {'trackIds': trackIds},
    );
    return MusicPlaylist.fromJson(parseData(response.data));
  }

  Future<MusicPlaylist> removePlaylistItems(
    String playlistId,
    List<String> trackIds,
  ) async {
    final response = await apiClient.dio.delete<Map<String, dynamic>>(
      '/music/playlists/$playlistId/items',
      data: {'trackIds': trackIds},
    );
    return MusicPlaylist.fromJson(parseData(response.data));
  }

  Future<MusicPlaybackPlan> playbackPlan(String trackId) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/music/tracks/$trackId/playback-plan',
    );
    return _resolvePlaybackPlan(parsePlaybackPlan(parseData(response.data)));
  }

  Future<void> favorite(String trackId) async {
    await apiClient.dio.post<Map<String, dynamic>>(
      '/music/tracks/$trackId/favorite',
    );
  }

  Future<void> removeFavorite(String trackId) async {
    await apiClient.dio.delete<Map<String, dynamic>>(
      '/music/tracks/$trackId/favorite',
    );
  }

  Future<TaskSubmission> deleteTrack(
    String trackId, {
    bool cascade = false,
  }) async {
    final response = await apiClient.dio.delete<Map<String, dynamic>>(
      '/music/tracks/$trackId',
      queryParameters: {'cascade': cascade},
    );
    return TaskSubmission.fromJson(parseData(response.data));
  }

  Future<void> updateTrack({
    required String trackId,
    String? title,
    String? artistName,
    String? albumTitle,
    String? genre,
    String? lyricsRaw,
    String? coverFileId,
  }) async {
    await apiClient.dio.put<Map<String, dynamic>>(
      '/admin/music/tracks/$trackId',
      data: {
        if (title != null) 'title': title,
        if (artistName != null) 'artistName': artistName,
        if (albumTitle != null) 'albumTitle': albumTitle,
        if (genre != null) 'genre': genre,
        if (lyricsRaw != null) 'lyricsRaw': lyricsRaw,
        if (coverFileId != null) 'coverFileId': coverFileId,
      },
    );
  }

  Future<String> uploadCover({
    required List<int> bytes,
    required String fileName,
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: fileName),
    });
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/music/covers',
      data: formData,
    );
    final data = parseData(response.data);
    return data['fileId'] as String;
  }

  Future<void> recordPlayHistory(String trackId, {int playDuration = 0}) async {
    await apiClient.dio.post<Map<String, dynamic>>(
      '/music/tracks/$trackId/play-history',
      data: {'playDuration': playDuration},
    );
  }

  Future<void> recordPlayableHistory({
    required String playableKey,
    required String title,
    required String artistName,
    required String albumTitle,
    required String coverUrl,
    required int? durationSeconds,

    int playDuration = 0,
  }) async {
    await apiClient.dio.post<Map<String, dynamic>>(
      '/music/play-history',
      data: <String, dynamic>{
        'playableKey': playableKey,
        'playDuration': playDuration,
        'title': title,
        'artistName': artistName,
        'albumTitle': albumTitle,
        'coverUrl': coverUrl,
        'durationSeconds': durationSeconds,
      },
    );
  }

  Future<MusicTrack?> lastPlayed() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/music/last-played',
    );
    final envelope = parseEnvelope(response.data);
    final data = envelope['data'];
    if (data is! Map<String, dynamic>) return null;
    return MusicTrack.fromJson(data);
  }

  Future<MusicPlaybackPosition> lastPosition() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/music/last-position',
    );
    return MusicPlaybackPosition.fromJson(parseData(response.data));
  }

  Future<MusicPlaybackQueueSnapshot> playbackQueue() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/music/playback-queue',
    );
    return MusicPlaybackQueueSnapshot.fromJson(parseData(response.data));
  }

  /// 保存播放队列并返回服务端规范化结果（含服务端时间戳）。
  Future<MusicPlaybackQueueSnapshot> savePlaybackQueue(
    MusicPlaybackQueueSnapshot snapshot,
  ) async {
    final response = await apiClient.dio.put<Map<String, dynamic>>(
      '/music/playback-queue',
      data: snapshot.toJson(),
    );
    return MusicPlaybackQueueSnapshot.fromJson(parseData(response.data));
  }

  Future<void> savePosition({
    required String trackId,
    required int positionSeconds,
  }) async {
    await apiClient.dio.put<Map<String, dynamic>>(
      '/music/position',
      data: {'trackId': trackId, 'positionSeconds': positionSeconds},
    );
  }

  /// 获取指定可播放对象的跨设备进度。
  Future<MusicPlaybackProgress?> playbackProgress(String playableKey) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/music/progress',
      queryParameters: {'playableKey': playableKey},
    );
    final data = parseEnvelope(response.data)['data'];
    if (data == null) {
      return null;
    }
    if (data is! Map) {
      throw const AppException(
        code: 'INVALID_RESPONSE',
        message: '音乐播放进度格式不正确',
      );
    }
    return MusicPlaybackProgress.fromJson(Map<String, dynamic>.from(data));
  }

  /// 保存本地或在线音乐的跨设备进度。
  Future<MusicPlaybackProgress> savePlaybackProgress(
    MusicPlaybackProgress progress,
  ) async {
    final deviceId = await PlaybackDeviceIdentity.getOrCreate();
    final response = await apiClient.dio.put<Map<String, dynamic>>(
      '/music/progress',
      data: {...progress.toSaveJson(), 'deviceId': deviceId},
    );
    return MusicPlaybackProgress.fromJson(parseData(response.data));
  }

  /// 获取音频流重定向 URL（302）。
  String streamUrl(String trackId) {
    return '${apiClient.dio.options.baseUrl}/music/stream/$trackId';
  }

  Future<MusicScanJob> createScanJob() async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/admin/music/scan',
    );
    return MusicScanJob.fromJson(parseData(response.data));
  }

  Future<MusicScanJob> scanJobStatus(String jobId) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/admin/music/scan/$jobId/status',
    );
    return MusicScanJob.fromJson(parseData(response.data));
  }

  Future<List<MusicScrapeCandidate>> scrapeCandidates(String trackId) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/admin/music/tracks/$trackId/scrape-candidates',
    );
    return _parseList(
      response.data,
      MusicScrapeCandidate.fromJson,
      '音乐刮削候选格式不正确',
    );
  }

  Future<MusicTrack> applyScrapeCandidate(
    String trackId,
    MusicScrapeCandidate candidate,
  ) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/admin/music/tracks/$trackId/scrape/apply',
      data: candidate.toApplyJson(),
    );
    return MusicTrack.fromJson(parseData(response.data));
  }

  Future<MusicScanJob> scrapeLibrary({bool force = false}) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/admin/music/scrape',
      data: {'force': force},
    );
    return MusicScanJob.fromJson(parseData(response.data));
  }

  /// 查询指定艺术家下的活动专辑列表。
  Future<List<MusicAlbum>> artistAlbums(String artistId) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/music/artists/$artistId/albums',
    );
    return _parseList(response.data, MusicAlbum.fromJson, '专辑列表格式不正确');
  }

  /// 按当前曲目的艺术家/标题/专辑搜索在线歌词候选。
  Future<MusicLyricsResult?> searchLyrics(String trackId) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/admin/music/tracks/$trackId/lyrics/search',
    );
    final envelope = parseEnvelope(response.data);
    final data = envelope['data'];
    if (data is! Map) {
      return null;
    }
    return MusicLyricsResult.fromJson(Map<String, dynamic>.from(data));
  }

  /// 应用歌词文本到指定曲目并返回更新后的曲目。
  Future<MusicTrack> applyLyrics(
    String trackId,
    String lyrics, {
    String? lyricsTranslation,
  }) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/admin/music/tracks/$trackId/lyrics/apply',
      data: {'lyrics': lyrics, 'lyricsTranslation': lyricsTranslation},
    );
    return MusicTrack.fromJson(parseData(response.data));
  }

  /// 在线搜索（网易云）
  Future<List<OnlineTrack>> onlineSearch(
    String query, {
    int limit = 20,
    String? platform,
    CancelToken? cancelToken,
  }) async {
    final params = <String, String>{'q': query, 'limit': limit.toString()};
    if (platform != null) params['platform'] = platform;
    final resp = await apiClient.dio.get<Map<String, dynamic>>(
      '/music/online/search',
      queryParameters: params,
      cancelToken: cancelToken,
    );
    final envelope = parseEnvelope(resp.data);
    final list = envelope['data'] is List ? envelope['data'] as List : [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(OnlineTrack.fromJson)
        .toList();
  }

  /// 获取在线播放URL
  Future<MusicPlaybackPlan> onlinePlaybackPlan(
    String platform,
    String songId, {

    String quality = 'exhigh',
  }) async {
    final params = <String, String>{
      'platform': platform,
      'songId': songId,
      'quality': quality,
    };

    final resp = await apiClient.dio.get<Map<String, dynamic>>(
      '/music/online/playback-plan',
      queryParameters: params,
    );
    return _resolvePlaybackPlan(parsePlaybackPlan(parseData(resp.data)));
  }

  /// 获取在线平台连接状态和能力
  Future<List<MusicPlatformStatus>> musicPlatforms() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/music/platforms',
    );
    return _parseList(
      response.data,
      MusicPlatformStatus.fromJson,
      '平台状态列表格式不正确',
    );
  }

  /// 获取在线平台歌单
  Future<MusicPagedResult<OnlinePlaylist>> platformPlaylists(
    String platform, {
    int page = 0,
    int size = 100,
  }) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/music/platforms/$platform/playlists',
      queryParameters: <String, dynamic>{'page': page, 'size': size},
    );
    return _parsePage(response.data, OnlinePlaylist.fromJson, '平台歌单列表格式不正确');
  }

  /// 获取在线平台歌单曲目
  Future<MusicPagedResult<OnlineTrack>> platformPlaylistTracks(
    String platform,
    String playlistId, {
    int page = 0,
    int size = 200,
  }) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/music/platforms/$platform/playlists/$playlistId/tracks',
      queryParameters: <String, dynamic>{'page': page, 'size': size},
    );
    return _parsePage(response.data, OnlineTrack.fromJson, '平台歌单曲目格式不正确');
  }

  /// 获取在线平台喜欢歌曲
  Future<MusicPagedResult<OnlineTrack>> platformLikedTracks(
    String platform, {
    int page = 0,
    int size = 1000,
  }) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/music/platforms/$platform/liked-tracks',
      queryParameters: <String, dynamic>{'page': page, 'size': size},
    );
    return _parsePage(response.data, OnlineTrack.fromJson, '平台喜欢歌曲格式不正确');
  }

  /// 获取外部平台每日推荐歌曲。
  Future<DailyRecommendedTracks> platformDailyRecommendedTracks(
    String platform,
  ) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/music/platforms/$platform/recommendations/daily-tracks',
    );
    return DailyRecommendedTracks.fromJson(parseData(response.data));
  }

  /// 获取外部平台歌词（原文、独立译文与逐字载荷）。
  Future<MusicPlatformLyrics?> platformTrackLyrics(
    String platform,
    String songId,
  ) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/music/platforms/$platform/tracks/$songId/lyrics',
    );
    final data = parseData(response.data);
    final synced = data['syncedLyrics']?.toString();
    final plain = data['plainLyrics']?.toString();
    final translated = data['translatedLyrics']?.toString();
    final primary =
        synced != null && synced.trim().isNotEmpty
            ? synced
            : (plain != null && plain.trim().isNotEmpty ? plain : null);
    if (primary == null) {
      return null;
    }
    // 逐字是可选载荷：后端在平台不提供（或附加接口失败）时为 null，
    // 在此统一归一为空，调用方只判断 null。
    return MusicPlatformLyrics(
      lyrics: primary,
      translation: _nonBlank(translated),
      words: _nonBlank(data['wordLyrics']?.toString()),
    );
  }

  static String? _nonBlank(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  /// 生成网易云 QR 登录
  Future<QrLoginSession> createNeteaseQrLogin() async {
    final resp = await apiClient.dio.post<Map<String, dynamic>>(
      '/music/platforms/netease/login-sessions',
    );
    return QrLoginSession.fromJson(parseData(resp.data));
  }

  /// 轮询网易云 QR 登录状态
  Future<QrLoginStatus> checkNeteaseQrLogin(String key) async {
    final resp = await apiClient.dio.get<Map<String, dynamic>>(
      '/music/platforms/netease/login-sessions/$key',
    );
    return QrLoginStatus.fromJson(parseData(resp.data));
  }

  /// 平台登出
  ///
  /// 标记为"服务端错误不重试"：断开连接是用户已确认的一次性动作，服务端 5xx 时
  /// 重试注定失败，却会把等待时间放大为退避之和（默认 2 次重试共 1s + 2s）。
  Future<void> platformLogout(String platform) async {
    await apiClient.dio.delete(
      '/music/platforms/$platform/connection',
      options: Options(extra: <String, dynamic>{skipServerErrorRetryKey: true}),
    );
  }

  /// 获取平台登录信息
  Future<PlatformUserInfo?> platformInfo(String platform) async {
    try {
      final resp = await apiClient.dio.get<Map<String, dynamic>>(
        '/music/platform/$platform/info',
      );
      final data = parseData(resp.data);
      if (data['userId'] == null || data['userId'].toString().isEmpty) {
        return null;
      }
      return PlatformUserInfo.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  static MusicPlaybackPlan parsePlaybackPlan(Map<String, dynamic> data) {
    return MusicPlaybackPlan.fromJson(data);
  }

  MusicPlaybackPlan _resolvePlaybackPlan(MusicPlaybackPlan plan) {
    return plan.copyWith(url: _resolvePlayableUrl(plan.url));
  }

  String _resolvePlayableUrl(String url) {
    if (url.isEmpty) {
      return url;
    }
    final parsed = Uri.tryParse(url);
    if (parsed != null && parsed.hasScheme) {
      return url;
    }
    final base = apiClient.dio.options.baseUrl;
    if (url.startsWith('/')) {
      final baseUri = Uri.parse(base);
      final origin = '${baseUri.scheme}://${baseUri.authority}';
      return '$origin${url.startsWith('/api/v1') ? url : '/api/v1$url'}';
    }
    final normalizedBase =
        base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return '$normalizedBase/$url';
  }

  Map<String, dynamic> parseData(Map<String, dynamic>? body) {
    final envelope = parseEnvelope(body);
    final data = envelope['data'];
    if (data is! Map<String, dynamic>) {
      throw const AppException(code: 'INVALID_RESPONSE', message: '音乐响应格式不正确');
    }
    return data;
  }

  Map<String, dynamic> parseEnvelope(Map<String, dynamic>? body) {
    if (body == null) {
      throw const AppException(code: 'EMPTY_RESPONSE', message: '服务端没有返回音乐结果');
    }
    final code = body['code'];
    if (code != 200) {
      throw AppException(
        code: code?.toString() ?? 'MUSIC_ERROR',
        message: body['message']?.toString() ?? '音乐操作失败',
      );
    }
    return body;
  }

  MusicPagedResult<T> _parsePage<T>(
    Map<String, dynamic>? body,
    T Function(Map<String, dynamic>) mapper,
    String errorMessage,
  ) {
    final data = parseEnvelope(body)['data'];
    if (data is! Map) {
      throw AppException(code: 'INVALID_RESPONSE', message: errorMessage);
    }
    final rawItems = data['items'];
    if (rawItems is! List) {
      throw AppException(code: 'INVALID_RESPONSE', message: errorMessage);
    }
    return MusicPagedResult<T>(
      items:
          rawItems
              .whereType<Map>()
              .map((item) => mapper(Map<String, dynamic>.from(item)))
              .toList(),
      page: _asIntOrNull(data['page']),
      size: _asIntOrNull(data['size']),
      totalElements: _asIntOrNull(data['totalElements']),
    );
  }

  int _asIntOrNull(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return 0;
  }

  List<T> _parseList<T>(
    Map<String, dynamic>? body,
    T Function(Map<String, dynamic>) mapper,
    String errorMessage,
  ) {
    final data = parseEnvelope(body)['data'];
    if (data is! List) {
      throw AppException(code: 'INVALID_RESPONSE', message: errorMessage);
    }
    return data
        .whereType<Map>()
        .map((item) => mapper(Map<String, dynamic>.from(item)))
        .toList();
  }
}
