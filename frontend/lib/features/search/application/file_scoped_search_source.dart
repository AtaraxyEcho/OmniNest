import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/search/scoped_search_source.dart';
import 'package:omninest/features/search/application/search_controller.dart';
import 'package:omninest/features/search/domain/search_result.dart';

/// 文件档来源：`/search` 是文件全文索引（Lucene，限当前用户）。
///
/// 覆盖层改走注册表之前只返回这一档结果，因此必须继续提供，否则换数据源
/// 就把已经可用的文件全文搜索砍掉了。落点只能在搜索模块内：文件模块
/// import 搜索模块的 data 会触 `CROSS_FEATURE_INTERNAL`。
class FileScopedSearchSource extends ScopedSearchSource {
  const FileScopedSearchSource();

  @override
  ScopedSearchId get scope => ScopedSearchId.file;

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
    // 全文索引接口不分页；第二页起返回空集，让「加载更多」自然停止。
    if (page > 0) {
      return const <ScopedSearchResult>[];
    }
    final results = await ref
        .read(searchApiProvider)
        .search(
          keyword,
          limit: ScopedSearchLimits.perSource,
          cancelToken: cancelToken,
        );
    return <ScopedSearchResult>[for (final item in results) _toScoped(item)];
  }

  /// 详情直达仍受后端契约限制：结果只带 fileId，没有可直达的节点路由，
  /// 因此沿用回到文件浏览器的行为（后端补 `entityId/scope` 后升级）。
  ScopedSearchResult _toScoped(SearchResult item) {
    return ScopedSearchResult(
      title: item.title,
      subtitle: item.subtitle.isEmpty ? null : item.subtitle,
      detailRoute: '/files',
      scope: ScopedSearchId.file,
    );
  }
}
