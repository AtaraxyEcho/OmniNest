import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/features/search/data/search_api.dart';
import 'package:omninest/features/search/domain/search_result.dart';

final searchApiProvider = Provider<SearchApi>((ref) {
  return SearchApi(ref.watch(apiClientProvider));
});

final searchQueryProvider =
    NotifierProvider.autoDispose<SearchQueryNotifier, String>(
      SearchQueryNotifier.new,
    );

class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void updateQuery(String value) => state = value;

  void clear() => state = '';
}

final searchResultsProvider = AsyncNotifierProvider.autoDispose<
  SearchResultsNotifier,
  List<SearchResult>
>(SearchResultsNotifier.new);

class SearchResultsNotifier extends AsyncNotifier<List<SearchResult>> {
  int _generation = 0;
  List<SearchResult> _lastResults = const [];
  CancelToken? _cancelToken;

  @override
  Future<List<SearchResult>> build() async {
    final query = ref.watch(searchQueryProvider).trim();
    final generation = ++_generation;
    _cancelToken?.cancel();
    _cancelToken = null;
    ref.onDispose(() => _cancelToken?.cancel());
    if (query.isEmpty) {
      _lastResults = const [];
      return _lastResults;
    }
    // 每个字符都打一次搜索接口会放大后端压力，并让旧响应有机会覆盖新结果；
    // 去抖后仍以 generation 丢弃过期响应，CancelToken 取消底层请求。
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (generation != _generation) {
      return _lastResults;
    }
    final cancelToken = CancelToken();
    _cancelToken = cancelToken;
    final api = ref.read(searchApiProvider);
    try {
      final results = await api.search(query, cancelToken: cancelToken);
      if (generation != _generation) {
        return _lastResults;
      }
      _lastResults = results;
      return results;
    } on Exception catch (error) {
      if (error is DioException && CancelToken.isCancel(error) ||
          generation != _generation) {
        return _lastResults;
      }
      rethrow;
    }
  }

  Future<void> search(String query) async {
    ref.read(searchQueryProvider.notifier).updateQuery(query);
    ref.invalidateSelf();
  }
}
