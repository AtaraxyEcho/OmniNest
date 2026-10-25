import 'package:dio/dio.dart';
import 'package:omninest/core/errors/envelope_guard.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/features/search/domain/search_result.dart';

class SearchApi {
  SearchApi(this._client);

  final ApiClient _client;

  Future<List<SearchResult>> search(
    String query, {
    int limit = 20,
    CancelToken? cancelToken,
  }) async {
    final response = await _client.dio.get<Map<String, dynamic>>(
      '/search',
      queryParameters: {'q': query, 'limit': limit},
      cancelToken: cancelToken,
    );
    final data = response.data;
    ensureEnvelopeSuccess(data, fallbackMessage: '搜索失败');
    final items = data!['data'] as List<dynamic>? ?? [];
    return items
        .whereType<Map>()
        .map((item) => _parse(Map<String, dynamic>.from(item)))
        .toList();
  }

  /// `/search` 当前是文件全文索引：返回 `fileId/title/snippet/score`。
  /// 保留对旧聚合结构的兼容，避免其他端的通用结果被误判为空类型。
  SearchResult _parse(Map<String, dynamic> json) {
    final type = json['type']?.toString();
    if (type != null && type.isNotEmpty) {
      return SearchResult.fromJson(json);
    }
    return SearchResult(
      id: json['fileId']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      subtitle: json['snippet']?.toString() ?? '',
      type: 'file',
    );
  }
}
