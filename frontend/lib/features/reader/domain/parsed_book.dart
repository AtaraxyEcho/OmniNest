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
    this.level = 0,
    this.sourceStartOffset,
    this.sourceEndOffset,
  });

  final int number;
  final String title;

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
}
