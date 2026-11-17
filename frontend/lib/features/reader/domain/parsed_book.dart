import 'dart:typed_data';

class ParsedBook {
  const ParsedBook({
    required this.chapters,
    this.title,
    this.author,
    this.description,
    this.publisher,
    this.language,
    this.coverBytes,
  });

  final String? title;
  final String? author;
  final String? description;
  final String? publisher;
  final String? language;
  final List<ParsedChapter> chapters;

  /// 封面图片字节（PNG/JPEG），用于上传到服务端
  final Uint8List? coverBytes;

  ParsedBook copyWith({
    List<ParsedChapter>? chapters,
    String? title,
    String? author,
    String? description,
    String? publisher,
    String? language,
    Uint8List? coverBytes,
  }) {
    return ParsedBook(
      chapters: chapters ?? this.chapters,
      title: title ?? this.title,
      author: author ?? this.author,
      description: description ?? this.description,
      publisher: publisher ?? this.publisher,
      language: language ?? this.language,
      coverBytes: coverBytes ?? this.coverBytes,
    );
  }
}

class ParsedChapter {
  const ParsedChapter({
    required this.number,
    required this.title,
    required this.xhtmlContent,
    required this.charCount,
    this.contentPath,
    this.chapterKey,
    this.level = 0,
    this.sourceStartOffset,
    this.sourceEndOffset,
    this.bodyStartOffset = 0,
  });

  final int number;
  final String title;

  /// 章节身份键，由服务端清单下发（TXT 按正文起点派生，EPUB 按归档顺位）。
  ///
  /// 阅读进度与批注存的就是它；不能用清单顺位当身份，否则解析规则一改、
  /// 后续每一章的顺位整体位移，旧进度会静默落到别的章节正文上。
  final String? chapterKey;

  /// 章节 XHTML 内容。由 [EpubParserService.parseChapter] 按需填充。
  final String xhtmlContent;

  /// 章节纯文本字符数（用于全书偏移计算）
  final int charCount;

  /// EPUB 内部路径（如 OEBPS/chapter1.xhtml）
  final String? contentPath;

  /// 嵌套层级：0=卷/顶级，1=章，2=节，3=小节
  final int level;

  /// TXT 规范化文本中的章节起始字符偏移。
  final int? sourceStartOffset;

  /// TXT 规范化文本中的章节结束字符偏移。
  final int? sourceEndOffset;

  /// TXT 正文起点相对 [sourceStartOffset] 的字符偏移：标题行及其终止符不计入正文。
  /// 服务端正文与本地兜底切片都按它剥标题，两条路径渲染结果一致（D-12）。
  final int bodyStartOffset;
}

/// 章节在阅读器里使用的稳定身份。
///
/// 一律取清单下发的 [ParsedChapter.chapterKey]；缺失时退回顺位键，只可能出现在
/// 未经服务端解析的本地产物上，不参与跨设备对齐。
String parsedChapterId(ParsedChapter chapter) {
  final key = chapter.chapterKey?.trim();
  if (key != null && key.isNotEmpty) {
    return key;
  }
  return 'chapter_${chapter.number - 1}';
}
