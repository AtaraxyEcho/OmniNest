import 'package:omninest/features/reader/domain/parsed_book.dart';

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

  /// 从清单章节创建阅读器章节。
  ///
  /// 身份一律取清单下发的稳定键：阅读器把进度与批注按它落库，用顺位当身份时
  /// 解析规则一改就会把旧进度搬到别的章节正文上。
  factory ReaderChapter.fromParsed(int index, ParsedChapter chapter) {
    return ReaderChapter(
      id: parsedChapterId(chapter),
      title: chapter.title,
      chapterNumber: index + 1,
      contentPath: chapter.contentPath,
      level: chapter.level,
    );
  }
}

/// 章节内容（由客户端 EPUB 解析提供，传递给渲染管线）
class ReaderChapterContent {
  const ReaderChapterContent({
    required this.title,
    required this.content,
    this.wordCount = 0,
    this.droppedImageCount,
    this.stylesheetCss = '',
  });

  final String title;
  final String content;
  final int wordCount;

  /// 这本书在**本章**生效的样式表全文，按本章 `<link>` 的次序拼好。
  ///
  /// 样式表不进 [content]：它存在书级池里，章节行只带次序引用，解析时经
  /// `parseBlocks(css:)` 传入。内联正文（TXT 与服务端下发的章节）没有样式表，
  /// 取空串。
  final String stylesheetCss;

  /// 本章因超出数量或容量上限而未加载的图片数；null 表示本次读取无法得知。
  ///
  /// 只有当章重新执行过图片预处理才有值：SQLite 命中时预处理不会重跑，
  /// 该章的缺图数没有可靠来源，此时按 null 处理而不是显示旧的计数。
  final int? droppedImageCount;

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

/// 封面候选图片（文件管理中已托管的图片节点，供"从文件选择封面"列出）
class ReaderCoverCandidate {
  const ReaderCoverCandidate({
    required this.fileNodeId,
    required this.fileName,
  });

  final String fileNodeId;
  final String fileName;
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
