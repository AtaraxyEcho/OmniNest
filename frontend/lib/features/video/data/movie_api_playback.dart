part of 'movie_api.dart';

const int _subtitleMaxBytes = FileSizeThresholds.subtitleMaxBytes;

/// 播放进度、观看历史与字幕。
mixin MovieApiPlayback on MovieApiBase {
  Future<List<MovieContinueWatching>> continueWatching() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/continue',
    );
    return parseList(response.data)
        .map((json) => MovieContinueWatching.fromJson(_resolvePosterJson(json)))
        .toList();
  }

  Future<List<MovieWatchHistory>> history() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/history',
    );
    return parseList(response.data)
        .map((json) => MovieWatchHistory.fromJson(_resolvePosterJson(json)))
        .toList();
  }

  /// 只查询单条视频的观看记录；没有记录时返回 null。
  Future<MovieWatchHistory?> itemHistory(String videoItemId) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/history/item/$videoItemId',
    );
    ensureEnvelopeSuccess(response.data, fallbackMessage: '加载观看历史失败');
    final data = response.data?['data'];
    if (data is! Map<String, dynamic>) {
      return null;
    }
    return MovieWatchHistory.fromJson(_resolvePosterJson(data));
  }

  /// 只查询某个系列下的观看历史，按播放时间倒序。
  Future<List<MovieWatchHistory>> seriesHistory(String seriesId) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/history/series/$seriesId',
    );
    return parseList(response.data)
        .map((json) => MovieWatchHistory.fromJson(_resolvePosterJson(json)))
        .toList();
  }

  /// 分页获取观看历史：滚动加载消费，按播放时间倒序。
  Future<MediaPage<MovieWatchHistory>> historyPage({
    int page = 0,
    int size = 50,
  }) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/history/page',
      queryParameters: {'page': page, 'size': size},
    );
    return MediaPage.fromJson(
      parseData(response.data),
      (json) => MovieWatchHistory.fromJson(_resolvePosterJson(json)),
    );
  }

  /// 删除指定观看历史（用户主动写）：无能力时抛 FORBIDDEN，禁止假成功。
  Future<void> deleteHistoryItem(String historyId) async {
    apiClient.requirePermission(activityWritePermission);
    final response = await apiClient.dio.delete<Map<String, dynamic>>(
      '/video/history/$historyId',
    );
    ensureEnvelopeSuccess(response.data, fallbackMessage: '删除观看历史失败');
  }

  /// 清空观看历史（用户主动写）：无能力时抛 FORBIDDEN。
  Future<void> clearHistory() async {
    apiClient.requirePermission(activityWritePermission);
    final response = await apiClient.dio.delete<Map<String, dynamic>>(
      '/video/history',
    );
    ensureEnvelopeSuccess(response.data, fallbackMessage: '清空观看历史失败');
  }

  Future<PlaybackPlan> playbackPlan(String videoItemId) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/video/items/$videoItemId/playback',
    );
    return PlaybackPlan.fromJson(parseData(response.data));
  }

  /// 更新播放进度（自动写回）。
  ///
  /// 无 `activity:write` 时静默 no-op：不发网络、不抛异常，调用方
  /// （进度同步服务 / 播放页）按成功处理。
  Future<void> updateProgress({
    required String videoItemId,
    required int positionSeconds,
    required int durationSeconds,
    bool completed = false,
  }) async {
    if (!apiClient.hasPermission(activityWritePermission)) {
      return;
    }
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
    parseEnvelope(response.data);
  }

  /// 读取有界字幕文本。
  Future<String> loadSubtitle(String url) async {
    final response = await apiClient.dio.get<ResponseBody>(
      url,
      options: Options(
        responseType: ResponseType.stream,
        headers: {'Range': 'bytes=0-${_subtitleMaxBytes - 1}'},
        validateStatus: (status) => status == 200 || status == 206,
        // 外挂字幕通常是对象存储预签名地址，不能把 Bearer JWT 和历史请求头带过去。
        extra:
            Uri.tryParse(url)?.hasAuthority == true
                ? const {ApiClient.skipAuthorizationKey: true}
                : null,
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
    return decodeTextFileBytes(bytes.takeBytes());
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
    final response = await apiClient.dio.delete<Map<String, dynamic>>(
      '/video/subtitles/$subtitleId',
    );
    ensureEnvelopeSuccess(response.data, fallbackMessage: '删除字幕失败');
  }
}
