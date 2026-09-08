import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/domain/reader_status_constants.dart';

class ReaderItemDetail {
  const ReaderItemDetail({
    required this.item,
    this.progress,
    this.chapters = const [],
  });

  factory ReaderItemDetail.fromJson(Map<String, dynamic> json) {
    return ReaderItemDetail(
      item: ReaderItem.fromJson(_asMap(json['item'])),
      progress:
          json['progress'] is Map
              ? ReaderProgress.fromJson(
                Map<String, dynamic>.from(json['progress'] as Map),
              )
              : null,
      chapters:
          json['chapters'] is List
              ? _parseChapters(json['chapters'] as List)
              : const [],
    );
  }

  final ReaderItem item;
  final ReaderProgress? progress;

  /// 章节列表（由客户端 EPUB 解析提供，后端不存储）
  final List<ReaderChapter> chapters;

  static List<ReaderChapter> _parseChapters(List<dynamic> list) {
    return list.whereType<Map>().map((item) {
      final map = Map<String, dynamic>.from(item);
      return ReaderChapter(
        id: map['id']?.toString() ?? '',
        title: map['title']?.toString() ?? '',
        chapterNumber: _asDouble(map['chapterNumber']),
        pageCount: _nullableInt(map['pageCount']),
        contentPath: map['contentPath']?.toString(),
      );
    }).toList();
  }
}

class ReaderItem {
  const ReaderItem({
    required this.id,
    required this.title,
    required this.itemType,
    required this.updatedAt,
    this.createdAt,
    this.fileNodeId,
    this.authorName,
    this.coverUrl,
    this.description,
    this.publisher,
    this.language,
    this.rating,
    this.progressPercent,
    this.addedToBookshelf = false,
    this.spaceType = 'PERSONAL',
    this.currentChapterTitle,
    this.metadataStatus,
    this.releaseDate,
    this.genres,
    this.serialStatus,
    this.contentKind = 'TEXT',
    this.importStatus,
    this.parseErrorCode,
    this.parseErrorMessage,
  });

  factory ReaderItem.fromJson(Map<String, dynamic> json) {
    return ReaderItem(
      id: json['id']?.toString() ?? '',
      fileNodeId: json['fileNodeId']?.toString(),
      itemType: json['itemType']?.toString() ?? 'EPUB',
      title: json['title']?.toString() ?? 'Untitled',
      authorName: json['authorName']?.toString(),
      coverUrl: json['coverUrl']?.toString(),
      description: json['description']?.toString(),
      publisher: json['publisher']?.toString(),
      language: json['language']?.toString(),
      rating: _nullableDouble(json['rating']),
      progressPercent: _nullableDouble(json['progressPercent']),
      createdAt: _parseDateTime(json['createdAt']),
      updatedAt: _parseDateTime(json['updatedAt']),
      addedToBookshelf: _asBool(json['addedToBookshelf']),
      spaceType: json['spaceType']?.toString() ?? 'PERSONAL',
      currentChapterTitle: json['currentChapterTitle']?.toString(),
      metadataStatus: json['metadataStatus']?.toString(),
      releaseDate: _parseDateTime(json['releaseDate']),
      genres: _parseStringList(json['genres']),
      serialStatus: json['serialStatus']?.toString(),
      contentKind: json['contentKind']?.toString() ?? 'TEXT',
      importStatus: json['importStatus']?.toString(),
      parseErrorCode: json['parseErrorCode']?.toString(),
      parseErrorMessage: json['parseErrorMessage']?.toString(),
    );
  }

  final String id;
  final DateTime? createdAt;
  final String? fileNodeId;
  final String itemType;
  final String title;
  final String? authorName;
  final String? coverUrl;
  final String? description;
  final String? publisher;
  final String? language;
  final double? rating;
  final double? progressPercent;
  final DateTime? updatedAt;

  /// 是否已加入书架
  final bool addedToBookshelf;

  /// 文件所属空间类型（PERSONAL / SHARED）
  final String spaceType;

  /// 当前阅读章节标题（仪表盘继续阅读时显示）
  final String? currentChapterTitle;

  /// 元数据刮削状态（PENDING / FAILED / MANUAL / MATCHED）
  final String? metadataStatus;

  /// 出版日期
  final DateTime? releaseDate;

  /// 分类标签列表
  final List<String>? genres;

  /// 连载状态（ONGOING / COMPLETED / UNKNOWN）
  final String? serialStatus;

  /// 内容类型（TEXT / COMIC）
  final String contentKind;

  /// 导入状态（READY / PARSING / PARTIAL_FAILED / FAILED）
  final String? importStatus;

  /// 最近一次解析错误码
  final String? parseErrorCode;

  /// 最近一次解析错误信息
  final String? parseErrorMessage;

  /// 是否有封面图
  bool get hasCover => coverUrl != null && coverUrl!.isNotEmpty;

  /// 是否为漫画类型
  bool get isComic => contentKind == 'COMIC';

  /// 是否正在解析
  bool get isParsing => importStatus == ReaderImportStatus.parsing;

  /// 是否部分失败（部分来源导入失败）
  bool get isPartialFailed => importStatus == ReaderImportStatus.partialFailed;

  /// 是否完全失败
  bool get isFailed => importStatus == ReaderImportStatus.failed;
}

int _asInt(dynamic value) => switch (value) {
  int() => value,
  num() => value.toInt(),
  _ => int.tryParse(value?.toString() ?? '') ?? 0,
};

double _asDouble(dynamic value) => switch (value) {
  double() => value,
  num() => value.toDouble(),
  _ => double.tryParse(value?.toString() ?? '') ?? 0.0,
};

int? _nullableInt(dynamic value) {
  if (value == null || value.toString().isEmpty) return null;
  return _asInt(value);
}

double? _nullableDouble(dynamic value) {
  if (value == null || value.toString().isEmpty) return null;
  return _asDouble(value);
}

bool _asBool(dynamic value) {
  if (value is bool) return value;
  return value?.toString().toLowerCase() == 'true';
}

DateTime? _parseDateTime(dynamic value) {
  if (value == null || value.toString().isEmpty) return null;
  return DateTime.tryParse(value.toString().replaceFirst(' ', 'T'))?.toLocal();
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is! Map) return const {};
  return Map<String, dynamic>.from(value);
}

List<String>? _parseStringList(dynamic value) {
  if (value is! List) return null;
  final result = value.whereType<String>().toList();
  return result.isEmpty ? null : result;
}
