import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/search/scoped_search_source.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/domain/movie_detail_routes.dart';
import 'package:omninest/features/video/domain/movie_library_models.dart';

/// 影视档来源：复用影片分页接口的标题关键词查询，结果由数据侧覆盖全库。
///
/// 剧集与动漫的服务端关键词参数尚未具备，仍由模块页内的已加载列表承担，
/// 不在此来源里假装全库。
class VideoScopedSearchSource extends ScopedSearchSource {
  const VideoScopedSearchSource();

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
    final result = await ref
        .read(movieApiProvider)
        .libraryPage(
          keyword: keyword,
          page: page,
          size: ScopedSearchLimits.perSource,
        );
    // 分页接口不接收 CancelToken：过期响应由调用方的 generation 丢弃。
    if (cancelToken?.isCancelled ?? false) {
      return const <ScopedSearchResult>[];
    }
    return <ScopedSearchResult>[
      for (final item in result.items)
        ScopedSearchResult(
          title: item.title,
          subtitle: _subtitleOf(item),
          detailRoute: movieDetailRouteFromIds(
            videoItemId: item.id,
            seriesId: item.seriesId,
          ),
          scope: ScopedSearchId.video,
        ),
    ];
  }
}

String _subtitleOf(MovieVideoItem item) {
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
