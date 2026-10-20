import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/search/scoped_search_source.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';

/// 书籍档来源：关键词交给服务端，覆盖个人与共享空间的全部条目。
///
/// 只查书名与作者（后端 `query` 口径），因此漫画与文本、EPUB 同档出现。
class ReaderScopedSearchSource extends ScopedSearchSource {
  const ReaderScopedSearchSource();

  @override
  ScopedSearchId get scope => ScopedSearchId.book;

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
        .read(readerApiProvider)
        .itemsPage(
          query: keyword,
          page: page,
          size: ScopedSearchLimits.perSource,
        );
    if (cancelToken?.isCancelled ?? false) {
      return const <ScopedSearchResult>[];
    }
    return <ScopedSearchResult>[
      for (final item in result.items)
        ScopedSearchResult(
          title: item.title,
          subtitle: item.authorName,
          detailRoute: '/reader/items/${item.id}',
          scope: ScopedSearchId.book,
        ),
    ];
  }
}
