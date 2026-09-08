export 'package:omninest/features/reader/domain/comic_models.dart';
export 'package:omninest/features/reader/domain/parsed_book.dart';
export 'package:omninest/features/reader/domain/reader_annotation.dart';
export 'package:omninest/features/reader/domain/reader_bookmark.dart';
export 'package:omninest/features/reader/domain/reader_dashboard.dart';
export 'package:omninest/features/reader/domain/reader_file_ticket.dart';
export 'package:omninest/features/reader/domain/reader_item.dart';
export 'package:omninest/features/reader/domain/reader_note.dart';
export 'package:omninest/features/reader/domain/reader_progress.dart';
export 'package:omninest/features/reader/domain/reader_stats.dart';

// ─── 阅读器 UI 辅助类型 ────────────────────────────────────────

/// 章节信息（由客户端 EPUB 解析提供）
class ReaderChapter {
  const ReaderChapter({
    required this.id,
    required this.title,
    this.chapterNumber = 0,
    this.pageCount,
    this.contentPath,
    this.level = 0,
  });

  final String id;
  final String title;
  final double chapterNumber;
  final int? pageCount;
  final String? contentPath;

  /// 嵌套层级：0=卷/顶级，1=章，2=节，3=小节
  final int level;

  /// 从 ParsedChapter 创建兼容实例
  factory ReaderChapter.fromParsed(
    int index,
    String title, {
    String? contentPath,
    int level = 0,
  }) {
    return ReaderChapter(
      id: 'chapter_$index',
      title: title,
      chapterNumber: index + 1,
      contentPath: contentPath,
      level: level,
    );
  }
}

/// 章节内容（由客户端 EPUB 解析提供，传递给渲染管线）
class ReaderChapterContent {
  const ReaderChapterContent({
    required this.title,
    required this.content,
    this.wordCount = 0,
  });

  final String title;
  final String content;
  final int wordCount;

  /// 从 ParsedChapter 创建兼容实例
  factory ReaderChapterContent.fromParsed(dynamic parsed) {
    return ReaderChapterContent(
      title: parsed.title?.toString() ?? '',
      content: parsed.xhtmlContent?.toString() ?? '',
      wordCount: parsed.charCount as int? ?? 0,
    );
  }
}

/// 导入候选文件（文件管理中存在但阅读器中未导入的文件）
class ReaderImportCandidate {
  const ReaderImportCandidate({
    required this.fileNodeId,
    required this.fileName,
    required this.itemType,
    this.sizeDisplay = '',
  });

  /// 从导入候选接口数据创建领域模型。
  factory ReaderImportCandidate.fromJson(Map<String, dynamic> json) {
    return ReaderImportCandidate(
      fileNodeId: json['fileNodeId']?.toString() ?? '',
      fileName: json['fileName']?.toString() ?? '',
      itemType: json['itemType']?.toString() ?? 'EPUB',
      sizeDisplay: json['sizeDisplay']?.toString() ?? '',
    );
  }

  final String fileNodeId;
  final String fileName;
  final String itemType;
  final String sizeDisplay;
}

/// 阅读排序方式
enum ReaderSortBy { recent, title }

/// 书库分段（书库内的内容类型筛选）
enum ReaderLibrarySegment {
  /// 全部内容
  all,

  /// 仅图书（非漫画）
  books,

  /// 仅漫画
  comics,
}
