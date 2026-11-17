class SearchResult {
  const SearchResult({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.type,
    this.thumbnailUrl,
    this.seriesId,
    this.mediaType,
  });

  factory SearchResult.fromJson(Map<String, dynamic> json) {
    return SearchResult(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      subtitle: json['subtitle']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      thumbnailUrl: json['thumbnailUrl']?.toString(),
      seriesId: json['seriesId']?.toString(),
      mediaType: json['mediaType']?.toString(),
    );
  }

  final String id;
  final String title;
  final String subtitle;
  final String type;
  final String? thumbnailUrl;

  /// 影视分集所属系列 id；用于进剧集详情选集。
  final String? seriesId;
  final String? mediaType;
}
