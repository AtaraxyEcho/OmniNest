import 'package:omninest/features/photos/domain/photo.dart';

/// 照片相册实体
class PhotoAlbum {
  const PhotoAlbum({
    required this.id,
    required this.name,
    required this.description,
    required this.photoCount,
    required this.createdAt,
    required this.updatedAt,
    this.coverUrl,
  });

  final String id;
  final String name;
  final String description;
  final String? coverUrl;
  final int photoCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory PhotoAlbum.fromJson(Map<String, dynamic> json) {
    return PhotoAlbum(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '未命名相册',
      description: json['description']?.toString() ?? '',
      coverUrl: json['coverUrl']?.toString(),
      photoCount: _asInt(json['photoCount']),
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '')?.toLocal(),
      updatedAt:
          DateTime.tryParse(json['updatedAt']?.toString() ?? '')?.toLocal(),
    );
  }

  /// 是否有封面
  bool get hasCover => coverUrl != null && coverUrl!.isNotEmpty;
}

/// 相册详情（含照片列表）
class PhotoAlbumDetail {
  const PhotoAlbumDetail({required this.album, required this.photos});

  final PhotoAlbum album;
  final List<PhotoItem> photos;

  factory PhotoAlbumDetail.fromJson(Map<String, dynamic> json) {
    return PhotoAlbumDetail(
      album: PhotoAlbum.fromJson(_asMap(json['album'])),
      photos: _asList(json['photos']).map(PhotoItem.fromJson).toList(),
    );
  }
}

int _asInt(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return Map<String, dynamic>.from(value);
  }
  if (value is Map) {
    return Map<String, dynamic>.fromEntries(
      value.entries.map(
        (entry) => MapEntry(entry.key.toString(), entry.value as dynamic),
      ),
    );
  }
  return const {};
}

List<Map<String, dynamic>> _asList(Object? value) {
  if (value is List) {
    return value
        .whereType<Map>()
        .map(
          (entry) => Map<String, dynamic>.fromEntries(
            entry.entries.map(
              (item) => MapEntry(item.key.toString(), item.value as dynamic),
            ),
          ),
        )
        .toList();
  }
  return const [];
}
