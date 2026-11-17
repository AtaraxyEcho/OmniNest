import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/video/domain/movie_library_models.dart';
import 'package:omninest/features/video/presentation/widgets/redesign/movie_redesign_poster_card.dart';

/// 后端 DTO 序列化契约校验：以 MovieSeriesDto / MovieStatsDto 的
/// Jackson 组件名为基准构造 mock 载荷，锁定前端解析器的字段对齐。
void main() {
  test('MovieSeriesDto 形状载荷可完整解析出收藏卡片所需字段', () {
    final json = <String, Object?>{
      'id': '66000000-0000-0000-0000-000000000001',
      'title': 'Diablo',
      'originalTitle': 'Diablo IV',
      'firstAirDate': '2023-06-05',
      'overview': '系列简介',
      'posterFileId': null,
      'backdropFileId': null,
      'metadataStatus': 'MATCHED',
      'updatedAt': '2026-09-08T10:00:00Z',
      'metadata': <String, Object?>{},
      'posterUrl': 'http://example.com/poster.jpg',
      'backdropUrl': null,
      'assets': {
        'POSTER': {
          'id': '88000000-0000-0000-0000-000000000001',
          'assetType': 'POSTER',
          'fileNodeId': null,
          'url': 'http://example.com/asset-poster.jpg',
          'provider': 'TMDB',
          'language': null,
          'primary': true,
          'metadata': <String, Object?>{},
        },
      },
      'genres': ['动作', '奇幻'],
      'castMembers': <Object>[],
      'crewMembers': <Object>[],
      'rating': 8.7,
      'voteCount': 1200,
      'contentRating': 'R18',
      'seriesType': 'ANIME',
      'isFavorite': true,
    };

    final series = MovieSeries.fromJson(json);
    expect(series.id, '66000000-0000-0000-0000-000000000001');
    expect(series.title, 'Diablo');
    expect(series.originalTitle, 'Diablo IV');
    // firstAirDate 解析出年份供卡片角标使用。
    expect(series.year, '2023');
    expect(series.overview, '系列简介');
    expect(series.metadataStatus, 'MATCHED');
    expect(series.seriesType, 'ANIME');
    expect(series.rating, 8.7);
    expect(series.genres, ['动作', '奇幻']);
    expect(series.isFavorite, isTrue);
    // assets 嵌套结构与海报回退链路（posterUrl 缺失时回退 assets.POSTER.url）。
    expect(series.assets['POSTER']?.url, 'http://example.com/asset-poster.jpg');

    final card = MovieRedesignCardData.fromSeries(series);
    expect(card.id, '66000000-0000-0000-0000-000000000001');
    expect(card.title, 'Diablo');
    expect(card.subtitle, 'Diablo IV');
    expect(card.year, '2023');
    expect(card.rating, 8.7);
    expect(card.posterUrl, 'http://example.com/poster.jpg');
  });

  test('海报 URL 缺失时卡片回退到 assets.POSTER.url', () {
    final series = MovieSeries.fromJson(<String, Object?>{
      'id': 'series-1',
      'title': '无海报系列',
      'metadataStatus': 'MATCHED',
      'metadata': <String, Object?>{},
      'posterUrl': null,
      'assets': {
        'POSTER': {
          'assetType': 'POSTER',
          'url': 'http://example.com/asset-only.jpg',
          'primary': true,
          'metadata': <String, Object?>{},
        },
      },
    });

    expect(series.posterImageUrl, 'http://example.com/asset-only.jpg');
    expect(
      MovieRedesignCardData.fromSeries(series).posterUrl,
      'http://example.com/asset-only.jpg',
    );
  });

  test('stats 载荷 favoritesCount 为影片与系列收藏合计且缺省兼容', () {
    final stats = MovieStats.fromJson(<String, Object?>{
      'movieCount': 12,
      'episodeCount': 40,
      'seriesCount': 6,
      'scrapeFailedCount': 1,
      'favoritesCount': 5,
      'historyCount': 9,
      'collectionsCount': 2,
      'continueWatchingCount': 3,
    });
    expect(stats.favoritesCount, 5);
    expect(stats.historyCount, 9);
    expect(stats.collectionsCount, 2);
    expect(stats.continueWatchingCount, 3);

    // 旧后端响应缺少新增键时解析兜底为 0，不抛异常。
    final legacy = MovieStats.fromJson(<String, Object?>{
      'movieCount': 12,
      'episodeCount': 40,
      'seriesCount': 6,
      'scrapeFailedCount': 1,
    });
    expect(legacy.favoritesCount, 0);
    expect(legacy.historyCount, 0);
    expect(legacy.collectionsCount, 0);
    expect(legacy.continueWatchingCount, 0);
  });
}
