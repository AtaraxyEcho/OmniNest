import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/video/domain/movie_detail_routes.dart';
import 'package:omninest/features/video/domain/movie_library_models.dart';

MovieVideoItem _item({
  required String id,
  String? seriesId,
  String mediaType = 'MOVIE',
}) {
  return MovieVideoItem(
    id: id,
    fileNodeId: 'file-$id',
    mediaType: mediaType,
    title: 't-$id',
    metadataStatus: 'READY',
    nfoStatus: 'DISABLED',
    updatedAt: DateTime(2026),
    metadata: const {},
    seriesId: seriesId,
  );
}

void main() {
  test('电影条目进入影片详情', () {
    expect(movieDetailRoute(_item(id: 'movie-1')), '/video/movie-1');
  });

  test('分集条目进入剧集详情并使用 seriesId', () {
    expect(
      movieDetailRoute(
        _item(id: 'episode-9', seriesId: 'series-3', mediaType: 'EPISODE'),
      ),
      '/video/series/series-3',
    );
  });

  test('空 seriesId 回落影片详情，不用分集 id 拼系列路由', () {
    expect(
      movieDetailRoute(_item(id: 'episode-9', seriesId: '')),
      '/video/episode-9',
    );
  });

  test('系列详情与播放路由格式稳定', () {
    expect(movieSeriesDetailRoute('s-1'), '/video/series/s-1');
    expect(moviePlayRoute('v-2'), '/video/v-2/play');
    expect(movieItemDetailRoute('v-3'), '/video/v-3');
  });

  test('按 id 字段分流：continue/history 等 DTO', () {
    expect(
      movieDetailRouteFromIds(videoItemId: 'ep-1', seriesId: 'series-8'),
      '/video/series/series-8',
    );
    expect(movieDetailRouteFromIds(videoItemId: 'mv-1'), '/video/mv-1');
    expect(
      movieDetailRouteFromIds(videoItemId: 'mv-1', seriesId: ''),
      '/video/mv-1',
    );
  });
}
