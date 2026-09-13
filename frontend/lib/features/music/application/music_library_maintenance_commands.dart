part of 'music_controller.dart';

/// 管理本地音乐曲库扫描和元数据刮削命令。
extension MusicLibraryMaintenanceCommands on MusicCenterController {
  /// 创建曲库扫描任务并刷新任务状态。
  Future<void> createScanJob() async {
    final current = _currentState;
    if (current == null) {
      return;
    }
    try {
      final job = await _api.createScanJob();
      final latest = await _api.scanJobStatus(job.id);
      final refreshed = await _loadState(
        section: current.section,
        currentItem: current.currentItem,
        playbackPlan: current.playbackPlan,
        isPlaying: current.isPlaying,
        playbackItems: current.playbackItems,
        playbackIndex: current.playbackIndex,
        repeatMode: current.repeatMode,
        shuffleEnabled: current.shuffleEnabled,
        lastScanJob: latest,
      );
      _replaceState(refreshed);
    } on Exception catch (error) {
      _setError(describeUserFacingError(error).message);
      rethrow;
    }
  }

  /// 查询指定曲目的元数据刮削候选项。
  Future<List<MusicScrapeCandidate>> scrapeCandidates(MusicTrack track) {
    return _api.scrapeCandidates(track.id);
  }

  /// 应用元数据刮削候选项并刷新曲库。
  Future<void> applyScrapeCandidate(
    MusicTrack track,
    MusicScrapeCandidate candidate,
  ) async {
    final current = _currentState;
    if (current == null) {
      return;
    }
    try {
      final updated = await _api.applyScrapeCandidate(track.id, candidate);
      final nextTracks =
          current.tracks
              .map((item) => item.id == updated.id ? updated : item)
              .toList();
      final nextCurrentItem =
          current.currentItem?.track.id == updated.id
              ? current.currentItem!.copyWith(track: updated)
              : current.currentItem;
      _replaceState(
        current.copyWith(tracks: nextTracks, currentItem: nextCurrentItem),
      );
      await refresh();
    } on Exception catch (error) {
      _setError(describeUserFacingError(error).message);
      rethrow;
    }
  }

  /// 搜索指定曲目的在线歌词候选。
  Future<MusicLyricsResult?> searchLyrics(MusicTrack track) {
    return _api.searchLyrics(track.id);
  }

  /// 应用在线歌词并刷新曲目元数据。
  Future<MusicTrack> applyLyrics(
    MusicTrack track,
    String lyrics, {
    String? lyricsTranslation,
  }) async {
    final current = _currentState;
    if (current == null) {
      return track;
    }
    try {
      final updated = await _api.applyLyrics(
        track.id,
        lyrics,
        lyricsTranslation: lyricsTranslation,
      );
      final nextTracks =
          current.tracks
              .map((item) => item.id == updated.id ? updated : item)
              .toList();
      _replaceState(current.copyWith(tracks: nextTracks));
      return updated;
    } on Exception catch (error) {
      _setError(describeUserFacingError(error).message);
      rethrow;
    }
  }

  /// 创建全曲库元数据刮削任务并刷新任务状态。
  Future<void> scrapeLibrary({bool force = false}) async {
    final current = _currentState;
    if (current == null) {
      return;
    }
    try {
      final job = await _api.scrapeLibrary(force: force);
      final refreshed = await _loadState(
        section: current.section,
        currentItem: current.currentItem,
        playbackPlan: current.playbackPlan,
        isPlaying: current.isPlaying,
        playbackItems: current.playbackItems,
        playbackIndex: current.playbackIndex,
        repeatMode: current.repeatMode,
        shuffleEnabled: current.shuffleEnabled,
        lastScanJob: job,
      );
      _replaceState(refreshed);
    } on Exception catch (error) {
      _setError(describeUserFacingError(error).message);
      rethrow;
    }
  }
}
