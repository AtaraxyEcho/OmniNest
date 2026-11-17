import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/search/scoped_search_source.dart';
import 'package:omninest/features/photos/application/photo_repository_providers.dart';

/// 相册档来源：查询词只交给服务端，结果覆盖全库（含按 EXIF、标签、地名命中的条目）。
class PhotoScopedSearchSource extends ScopedSearchSource {
  const PhotoScopedSearchSource();

  @override
  ScopedSearchId get scope => ScopedSearchId.photo;

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
        .read(photoRepositoryProvider)
        .listPhotos(
          query: keyword,
          page: page,
          size: ScopedSearchLimits.perSource,
        );
    if (cancelToken?.isCancelled ?? false) {
      return const <ScopedSearchResult>[];
    }
    return <ScopedSearchResult>[
      for (final photo in result.items)
        ScopedSearchResult(
          title: photo.title,
          subtitle: photo.description,
          detailRoute: '/photos/${photo.id}',
          scope: ScopedSearchId.photo,
        ),
    ];
  }
}
