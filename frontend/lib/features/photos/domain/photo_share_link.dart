import 'package:omninest/features/photos/domain/photo.dart';

/// 照片分享链接模型
class PhotoShareLink {
  const PhotoShareLink({
    required this.id,
    required this.token,
    required this.resourceType,
    required this.resourceId,
    required this.accessCount,
    required this.createdAt,
    this.expiresAt,
    this.maxAccessCount,
    this.includeLocation = true,
    this.originalQuality = true,
  });

  final String id;
  final String token;
  final String resourceType;
  final String resourceId;
  final DateTime? expiresAt;
  final int? maxAccessCount;
  final int accessCount;
  final DateTime? createdAt;

  /// 公开访问是否包含位置。
  final bool includeLocation;

  /// 公开访问是否签发原图。
  final bool originalQuality;

  factory PhotoShareLink.fromJson(Map<String, dynamic> json) {
    return PhotoShareLink(
      id: json['id']?.toString() ?? '',
      token: json['token']?.toString() ?? '',
      resourceType: json['resourceType']?.toString() ?? '',
      resourceId: json['resourceId']?.toString() ?? '',
      expiresAt: DateTime.tryParse(json['expiresAt']?.toString() ?? ''),
      maxAccessCount:
          json['maxAccessCount'] == null
              ? null
              : (json['maxAccessCount'] as num).toInt(),
      accessCount:
          json['accessCount'] is num ? (json['accessCount'] as num).toInt() : 0,
      includeLocation: json['includeLocation'] != false,
      originalQuality: json['originalQuality'] != false,
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '')?.toLocal(),
    );
  }

  /// 是否已过期
  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());

  /// 是否已达到访问上限
  bool get isExhausted =>
      maxAccessCount != null && accessCount >= maxAccessCount!;
}

/// 共享相册数据模型
class PhotoSharedAlbum {
  const PhotoSharedAlbum({
    required this.albumName,
    required this.photos,
    this.description,
    this.page = 0,
    this.size = 50,
    this.total = 0,
  });

  final String albumName;
  final String? description;
  final List<PhotoItem> photos;
  final int page;
  final int size;
  final int total;

  factory PhotoSharedAlbum.fromJson(Map<String, dynamic> json) {
    return PhotoSharedAlbum(
      albumName: json['albumName']?.toString() ?? '',
      description: json['description']?.toString(),
      page: (json['page'] as num?)?.toInt() ?? 0,
      size: (json['size'] as num?)?.toInt() ?? 50,
      total: (json['total'] as num?)?.toInt() ?? 0,
      photos:
          json['photos'] is List
              ? (json['photos'] as List)
                  .whereType<Map>()
                  .map((e) => PhotoItem.fromJson(Map<String, dynamic>.from(e)))
                  .toList()
              : [],
    );
  }
}
