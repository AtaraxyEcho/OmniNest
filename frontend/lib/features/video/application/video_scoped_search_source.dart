import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/search/scoped_search_source.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/data/movie_api.dart';
import 'package:omninest/features/video/domain/movie_detail_routes.dart';
import 'package:omninest/features/video/domain/movie_library_models.dart';

/// 影视档来源：一次检索并行覆盖影片、剧集与动漫，三个粒度都在 SQL 侧过滤。
///
/// 影片走 `/video/library/page?q=`；该端点把 mediaType 硬归一到 MOVIE，所以系列名
/// 搜不到，剧集与动漫另走 `/video/series/by-type/page?q=`。
class VideoScopedSearchSource extends ScopedSearchSource {
  const VideoScopedSearchSource();

  /// 档内份额合计等于 `ScopedSearchLimits.perSource`，让三个粒度都必然有位置，
  /// 而不是影片占满后系列永远不出现。
  static const int _movieSlots = 10;
  static const int _seriesSlots = 5;

  @override
  ScopedSearchId get scope => ScopedSearchId.video;

  @override
  Future<List<ScopedSearchResult>> search(
    Ref ref,
    String query, {
    int page = 0,
    CancelToken? cancelToken,
  }) async {
    final keyword = query.trim();
    if (keyword.isEmpty) {
      return const <ScopedSearchResult>[];
    }
    final api = ref.read(movieApiProvider);
    final groups = await Future.wait(<Future<List<ScopedSearchResult>>>[
      _movies(api, keyword, page),
      _series(api, 'TV', keyword, page),
      _series(api, 'ANIME', keyword, page),
    ]);
    // 分页接口不接收 CancelToken：过期响应由调用方的 generation 丢弃。
    if (cancelToken?.isCancelled ?? false) {
      return const <ScopedSearchResult>[];
    }
    return groups
        .expand((group) => group)
        .take(ScopedSearchLimits.perSource)
        .toList(growable: false);
  }

  Future<List<ScopedSearchResult>> _movies(
    MovieApi api,
    String keyword,
    int page,
  ) async {
    final result = await api.libraryPage(
      keyword: keyword,
      page: page,
      size: _movieSlots,
    );
    return <ScopedSearchResult>[
      for (final item in result.items)
        ScopedSearchResult(
          title: item.title,
          subtitle: _movieSubtitleOf(item),
          detailRoute: movieDetailRouteFromIds(
            videoItemId: item.id,
            seriesId: item.seriesId,
          ),
          scope: ScopedSearchId.video,
        ),
    ];
  }

  Future<List<ScopedSearchResult>> _series(
    MovieApi api,
    String seriesType,
    String keyword,
    int page,
  ) async {
    final result = await api.seriesByTypePage(
      seriesType: seriesType,
      keyword: keyword,
      page: page,
      size: _seriesSlots,
    );
    return <ScopedSearchResult>[
      for (final series in result.items)
        ScopedSearchResult(
          title: series.title,
          subtitle: _seriesSubtitleOf(series),
          detailRoute: movieSeriesDetailRoute(series.id),
          scope: ScopedSearchId.video,
        ),
    ];
  }
}

String _movieSubtitleOf(MovieVideoItem item) {
  final runtimeMinutes =
      item.runtimeSeconds == null ? null : item.runtimeSeconds! ~/ 60;
  final parts = <String>[
    item.year,
    if (runtimeMinutes != null && runtimeMinutes > 0) '$runtimeMinutes min',
    if (item.rating != null && item.rating! > 0)
      '★ ${item.rating!.toStringAsFixed(1)}',
  ];
  return parts.join(' · ');
}

String _seriesSubtitleOf(MovieSeries series) {
  final parts = <String>[
    if (series.firstAirDate != null) '${series.firstAirDate!.year}',
    if (series.rating != null && series.rating! > 0)
      '★ ${series.rating!.toStringAsFixed(1)}',
  ];
  return parts.join(' · ');
}
