import 'package:omninest/features/video/domain/movie_library_models.dart';

/// 系列详情 PLAY 的目标类型。
enum SeriesPlayIntentKind {
  /// 续播未看完分集（continue 列表或历史未完成）。
  resume,

  /// 最近一集已看完，播放下一集。
  nextEpisode,

  /// 无观看记录，从第一集可播分集开始。
  first,
}

/// 系列 PLAY 意图：按钮文案与跳转目标的解析结果。
class SeriesPlayIntent {
  const SeriesPlayIntent({
    required this.kind,
    this.videoItemId,
    this.afterVideoItemId,
  });

  final SeriesPlayIntentKind kind;

  /// resume 时直接播放的分集 id。
  final String? videoItemId;

  /// nextEpisode 时的锚点分集 id（已看完）。
  final String? afterVideoItemId;
}

/// 解析系列 PLAY 意图（不发起播放）。
///
/// 优先级：continue 未完成 → 历史未完成 → 历史已完成（下一集）→ 首集。
/// [continueWatching] 服务端仅返回未完成进度；[history] 含 completed 标记。
SeriesPlayIntent resolveSeriesPlayIntent({
  required String seriesId,
  required List<MovieContinueWatching> continueWatching,
  required List<MovieWatchHistory> history,
}) {
  final resume =
      continueWatching.where((item) => item.seriesId == seriesId).firstOrNull;
  if (resume != null) {
    return SeriesPlayIntent(
      kind: SeriesPlayIntentKind.resume,
      videoItemId: resume.id,
    );
  }

  final seriesHistory =
      history.where((item) => item.seriesId == seriesId).toList()..sort((a, b) {
        final at = a.playedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b.playedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bt.compareTo(at);
      });
  final latest = seriesHistory.firstOrNull;
  if (latest != null && !latest.completed) {
    return SeriesPlayIntent(
      kind: SeriesPlayIntentKind.resume,
      videoItemId: latest.videoItemId,
    );
  }
  if (latest != null && latest.completed) {
    return SeriesPlayIntent(
      kind: SeriesPlayIntentKind.nextEpisode,
      afterVideoItemId: latest.videoItemId,
    );
  }
  return const SeriesPlayIntent(kind: SeriesPlayIntentKind.first);
}

/// 在按季/集排序的分集列表中选出实际可播的 videoItemId。
///
/// [afterVideoItemId] 非空时取其后的第一个可播分集；为空或找不到锚点时取第一个可播分集。
String? pickSeriesPlayEpisodeId({
  required List<MovieVideoItem> orderedEpisodes,
  String? afterVideoItemId,
}) {
  final playable = orderedEpisodes.where((episode) => episode.available);
  if (afterVideoItemId == null || afterVideoItemId.isEmpty) {
    return playable.firstOrNull?.id;
  }
  final anchorIndex = orderedEpisodes.indexWhere(
    (episode) => episode.id == afterVideoItemId,
  );
  if (anchorIndex < 0) {
    return playable.firstOrNull?.id;
  }
  for (var i = anchorIndex + 1; i < orderedEpisodes.length; i++) {
    final episode = orderedEpisodes[i];
    if (episode.available) {
      return episode.id;
    }
  }
  return null;
}

/// 将分集按季号、集号升序排序，供 PLAY 锚点定位使用。
List<MovieVideoItem> sortEpisodesForPlay(List<MovieVideoItem> episodes) {
  return [...episodes]..sort((a, b) {
    final season = (a.seasonNumber ?? 0).compareTo(b.seasonNumber ?? 0);
    if (season != 0) {
      return season;
    }
    return (a.episodeNumber ?? 0).compareTo(b.episodeNumber ?? 0);
  });
}

/// 分集内容不可用原因（对应 `availability_status`，见 V001）。
enum EpisodeUnavailableReason {
  none,
  fileMissing,
  fileChanged,
  sourceUnavailable,
}

/// 将 availabilityStatus 映射为不可用原因；AVAILABLE 为 none。
EpisodeUnavailableReason episodeUnavailableReason(String availabilityStatus) {
  return switch (availabilityStatus.toUpperCase()) {
    'AVAILABLE' => EpisodeUnavailableReason.none,
    'MISSING' || 'MISSING_PENDING' => EpisodeUnavailableReason.fileMissing,
    'CHANGED' => EpisodeUnavailableReason.fileChanged,
    'BLOCKED' || 'UNAVAILABLE' => EpisodeUnavailableReason.sourceUnavailable,
    _ => EpisodeUnavailableReason.sourceUnavailable,
  };
}
