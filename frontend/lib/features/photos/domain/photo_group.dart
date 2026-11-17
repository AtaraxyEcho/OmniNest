import 'package:omninest/features/photos/domain/photo.dart';

/// 照片分组数据
class PhotoGroup {
  const PhotoGroup({
    required this.groupKey,
    required this.photoCount,
    required this.photos,
  });

  final String groupKey;
  final int photoCount;
  final List<PhotoItem> photos;

  factory PhotoGroup.fromJson(Map<String, dynamic> json) {
    return PhotoGroup(
      groupKey: json['groupKey']?.toString() ?? '',
      photoCount:
          json['photoCount'] is num ? (json['photoCount'] as num).toInt() : 0,
      photos:
          (json['photos'] as List?)
              ?.whereType<Map>()
              .map((e) => PhotoItem.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          [],
    );
  }
}

/// 照片分组分页。
class PhotoGroupPage {
  const PhotoGroupPage({
    required this.items,
    required this.page,
    required this.size,
    required this.totalElements,
    required this.totalPages,
  });

  final List<PhotoGroup> items;
  final int page;
  final int size;
  final int totalElements;
  final int totalPages;

  factory PhotoGroupPage.fromJson(Map<String, dynamic> json) {
    return PhotoGroupPage(
      items:
          (json['items'] as List?)
              ?.whereType<Map>()
              .map(
                (item) => PhotoGroup.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList(growable: false) ??
          const [],
      page: json['page'] is num ? (json['page'] as num).toInt() : 0,
      size: json['size'] is num ? (json['size'] as num).toInt() : 50,
      totalElements:
          json['totalElements'] is num
              ? (json['totalElements'] as num).toInt()
              : 0,
      totalPages:
          json['totalPages'] is num ? (json['totalPages'] as num).toInt() : 0,
    );
  }
}

/// 分组维度枚举
enum GroupBy {
  date('DATE'),
  location('LOCATION'),
  format('FORMAT'),
  tag('TAG');

  const GroupBy(this.value);
  final String value;
}
