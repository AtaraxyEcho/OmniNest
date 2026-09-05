import 'package:omninest/features/photos/domain/photo_content_analysis.dart';

/// 照片实体模型。
class PhotoItem {
  const PhotoItem({
    required this.id,
    required this.fileNodeId,
    required this.title,
    required this.format,
    required this.fileSize,
    required this.metadataStatus,
    required this.favorite,
    required this.createdAt,
    this.description,
    this.width,
    this.height,
    this.orientation,
    this.dateTaken,
    this.cameraMake,
    this.cameraModel,
    this.aperture,
    this.shutterSpeed,
    this.iso,
    this.focalLength,
    this.flash,
    this.whiteBalance,
    this.meteringMode,
    this.lensModel,
    this.gpsLatitude,
    this.gpsLongitude,
    this.coverUrl,
    this.sourceUrl,
    this.gpsLocation,
    this.tags = const [],
    this.providerMetadata,
    this.contentAnalysis,
  });

  final String id;
  final String fileNodeId;
  final String title;
  final String? description;
  final int? width;
  final int? height;
  final int? orientation;
  final DateTime? dateTaken;
  final String? cameraMake;
  final String? cameraModel;
  final String? aperture;
  final String? shutterSpeed;
  final int? iso;
  final String? focalLength;
  final String? flash;
  final String? whiteBalance;
  final String? meteringMode;
  final String? lensModel;
  final double? gpsLatitude;
  final double? gpsLongitude;
  final String format;
  final int fileSize;
  final String? coverUrl;
  final String? sourceUrl;
  final String metadataStatus;
  final bool favorite;
  final DateTime? createdAt;
  final Map<String, dynamic>? gpsLocation;
  final List<String> tags;
  final Map<String, dynamic>? providerMetadata;
  final PhotoContentAnalysis? contentAnalysis;

  factory PhotoItem.fromJson(Map<String, dynamic> json) {
    return PhotoItem(
      id: json['id']?.toString() ?? '',
      fileNodeId: json['fileNodeId']?.toString() ?? '',
      title: json['title']?.toString() ?? '未命名照片',
      description: json['description']?.toString(),
      width: json['width'] == null ? null : _asInt(json['width']),
      height: json['height'] == null ? null : _asInt(json['height']),
      orientation:
          json['orientation'] == null ? null : _asInt(json['orientation']),
      dateTaken:
          DateTime.tryParse(json['dateTaken']?.toString() ?? '')?.toLocal(),
      cameraMake: json['cameraMake']?.toString(),
      cameraModel: json['cameraModel']?.toString(),
      aperture: json['aperture']?.toString(),
      shutterSpeed: json['shutterSpeed']?.toString(),
      iso: json['iso'] == null ? null : _asInt(json['iso']),
      focalLength: json['focalLength']?.toString(),
      flash: json['flash']?.toString(),
      whiteBalance: json['whiteBalance']?.toString(),
      meteringMode: json['meteringMode']?.toString(),
      lensModel: json['lensModel']?.toString(),
      gpsLatitude:
          json['gpsLatitude'] == null
              ? null
              : (json['gpsLatitude'] as num).toDouble(),
      gpsLongitude:
          json['gpsLongitude'] == null
              ? null
              : (json['gpsLongitude'] as num).toDouble(),
      format: json['format']?.toString() ?? 'JPEG',
      fileSize: json['fileSize'] == null ? 0 : _asInt(json['fileSize']),
      coverUrl: json['coverUrl']?.toString(),
      sourceUrl: json['sourceUrl']?.toString(),
      metadataStatus: json['metadataStatus']?.toString() ?? 'PENDING',
      favorite: json['favorite'] == true,
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '')?.toLocal(),
      gpsLocation:
          json['gpsLocation'] is Map
              ? Map<String, dynamic>.from(json['gpsLocation'] as Map)
              : null,
      tags:
          json['tags'] is List
              ? (json['tags'] as List).map((e) => e.toString()).toList()
              : const [],
      providerMetadata:
          json['providerMetadata'] is Map
              ? Map<String, dynamic>.from(json['providerMetadata'] as Map)
              : null,
      contentAnalysis:
          json['contentAnalysis'] is Map
              ? PhotoContentAnalysis.fromJson(
                Map<String, dynamic>.from(json['contentAnalysis'] as Map),
              )
              : null,
    );
  }

  /// 是否有封面
  bool get hasCover => coverUrl != null && coverUrl!.isNotEmpty;

  /// 缩略图缓存键忽略预签名参数，仅在后端对象路径变化时失效。
  String get coverCacheKey {
    final value = coverUrl;
    if (value == null || value.isEmpty) {
      return 'photo-cover:$id';
    }
    final uri = Uri.tryParse(value);
    final objectPath = uri?.path.trim();
    return 'photo-cover:$id:${objectPath?.isNotEmpty == true ? objectPath : value}';
  }

  /// 原图缓存键不包含临时签名参数，避免详情页重复下载同一文件。
  String get sourceCacheKey => 'photo-source:$id';

  /// 下载原片时建议的文件名；标题缺少扩展名时按格式补全。
  String get downloadFileName {
    final name = title.trim();
    final ext = format.toLowerCase();
    if (ext.isEmpty) {
      return name;
    }
    if (name.toLowerCase().endsWith('.$ext')) {
      return name;
    }
    // 标题自带其他写法的扩展名（如 .jpg 与格式 jpeg）时不重复追加。
    final dotIndex = name.lastIndexOf('.');
    final suffix = dotIndex < 0 ? '' : name.substring(dotIndex + 1);
    final looksLikeExtension =
        dotIndex > 0 &&
        suffix.length >= 2 &&
        suffix.length <= 5 &&
        RegExp(r'^[A-Za-z0-9]+$').hasMatch(suffix);
    return looksLikeExtension ? name : '$name.$ext';
  }

  /// 文件大小可读格式
  String get fileSizeDisplay {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// 分辨率可读格式
  String? get resolutionDisplay {
    if (width == null || height == null) return null;
    return '$width × $height';
  }

  /// EXIF 信息是否可用
  bool get hasExif =>
      cameraMake != null ||
      cameraModel != null ||
      aperture != null ||
      shutterSpeed != null ||
      iso != null ||
      focalLength != null;

  /// 是否有GPS坐标
  bool get hasGps => gpsLatitude != null && gpsLongitude != null;

  /// 是否有高级EXIF信息（闪光灯、白平衡、测光模式、镜头型号）
  bool get hasAdvancedExif =>
      flash != null ||
      whiteBalance != null ||
      meteringMode != null ||
      lensModel != null;

  /// 旧版场景标签兼容读取。
  @Deprecated('使用 contentAnalysis')
  List<String> get sceneLabels {
    if (providerMetadata == null) return const [];
    final labels = providerMetadata!['sceneLabels'];
    if (labels is List) {
      return labels
          .map((entry) {
            if (entry is Map) {
              return entry['name']?.toString().trim() ?? '';
            }
            return entry?.toString().trim() ?? '';
          })
          .where((label) => label.isNotEmpty)
          .toSet()
          .toList(growable: false);
    }
    return const [];
  }

  /// 位置显示文本；[preferZh] 为 true 时优先取中文字段，单个字段缺失时回退英文。
  String? locationDisplay({bool preferZh = false}) {
    if (gpsLocation == null || gpsLocation!.isEmpty) return null;
    String? pick(String key, String? zhKey) {
      if (preferZh && zhKey != null) {
        final zh = gpsLocation![zhKey]?.toString().trim();
        if (zh != null && zh.isNotEmpty) return zh;
      }
      final value = gpsLocation![key]?.toString().trim();
      return (value != null && value.isNotEmpty) ? value : null;
    }

    final parts = <String?>[
          pick('country', 'countryZh'),
          pick('state', 'stateZh'),
          pick('city', 'cityZh'),
          pick('district', 'districtZh'),
        ]
        .whereType<String>()
        .where((part) => part.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (parts.isNotEmpty) return parts.join(' · ');
    return pick('displayName', 'displayNameZh');
  }
}

/// 照片轻量列表分页。
class PhotoPage {
  const PhotoPage({
    required this.items,
    required this.page,
    required this.size,
    required this.totalElements,
    required this.totalPages,
  });

  factory PhotoPage.empty({int size = 50}) {
    return PhotoPage(
      items: const <PhotoItem>[],
      page: 0,
      size: size,
      totalElements: 0,
      totalPages: 0,
    );
  }

  factory PhotoPage.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return PhotoPage(
      items:
          rawItems is List
              ? rawItems
                  .whereType<Map<String, dynamic>>()
                  .map(PhotoItem.fromJson)
                  .toList(growable: false)
              : const <PhotoItem>[],
      page: _asInt(json['page']),
      size: _asInt(json['size']),
      totalElements: _asInt(json['totalElements']),
      totalPages: _asInt(json['totalPages']),
    );
  }

  final List<PhotoItem> items;
  final int page;
  final int size;
  final int totalElements;
  final int totalPages;

  bool get hasMore => page + 1 < totalPages;
}

/// 照片仪表盘数据
class PhotoDashboard {
  const PhotoDashboard({
    required this.totalPhotos,
    required this.totalAlbums,
    required this.totalFavorites,
    this.trashCount = 0,
    required this.recentPhotos,
    required this.favoritePhotos,
  });

  factory PhotoDashboard.empty() {
    return const PhotoDashboard(
      totalPhotos: 0,
      totalAlbums: 0,
      totalFavorites: 0,
      recentPhotos: [],
      favoritePhotos: [],
    );
  }

  final int totalPhotos;
  final int totalAlbums;
  final int totalFavorites;
  final int trashCount;
  final List<PhotoItem> recentPhotos;
  final List<PhotoItem> favoritePhotos;

  factory PhotoDashboard.fromJson(Map<String, dynamic> json) {
    return PhotoDashboard(
      totalPhotos: _asInt(json['totalPhotos']),
      totalAlbums: _asInt(json['totalAlbums']),
      totalFavorites: _asInt(json['totalFavorites']),
      trashCount: _asInt(json['trashCount']),
      recentPhotos:
          _asList(json['recentPhotos']).map(PhotoItem.fromJson).toList(),
      favoritePhotos:
          _asList(json['favoritePhotos']).map(PhotoItem.fromJson).toList(),
    );
  }
}

int _asInt(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
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
