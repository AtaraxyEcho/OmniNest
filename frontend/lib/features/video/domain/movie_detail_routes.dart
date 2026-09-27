import 'package:omninest/features/video/domain/movie_library_models.dart';

/// 系列详情路由：用于剧集/动画选集。
String movieSeriesDetailRoute(String seriesId) => '/video/series/$seriesId';

/// 影片播放路由。
String moviePlayRoute(String videoItemId) => '/video/$videoItemId/play';

/// 单片详情路由。
String movieItemDetailRoute(String videoItemId) => '/video/$videoItemId';

/// 按 id 字段拼详情路由（continue/history 等 DTO 场景）。
///
/// 分集（非空 [seriesId]）进剧集详情；否则进影片详情。
String movieDetailRouteFromIds({
  required String videoItemId,
  String? seriesId,
}) {
  if (seriesId != null && seriesId.isNotEmpty) {
    return movieSeriesDetailRoute(seriesId);
  }
  return movieItemDetailRoute(videoItemId);
}

/// 影视条目详情路由。
///
/// 分集（持有 [MovieVideoItem.seriesId]）进剧集详情以选择季/集；
/// 电影进影片详情。禁止用分集的 video item id 拼系列路由。
String movieDetailRoute(MovieVideoItem item) {
  return movieDetailRouteFromIds(videoItemId: item.id, seriesId: item.seriesId);
}
