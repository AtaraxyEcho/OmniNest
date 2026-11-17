import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/application/reader_book_provider.dart';
import 'package:omninest/features/reader/data/txt_parser_service.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';

void main() {
  ParsedBook buildBook({String? secondPath = 'OPS/chapter-2.xhtml'}) {
    return ParsedBook(
      chapters: [
        const ParsedChapter(
          number: 1,
          title: '第一章',
          xhtmlContent: '',
          charCount: 100,
          contentPath: 'OPS/chapter-1.xhtml',
        ),
        ParsedChapter(
          number: 2,
          title: '第二章',
          xhtmlContent: '',
          charCount: 120,
          contentPath: secondPath,
        ),
      ],
    );
  }

  group('章节落库体积上限', () {
    test('上限只按正文规模给，异常大的正文仍然拒绝', () {
      // 样式表不进正文（书级池 + 章节次序引用），所以这一档没有样式表的放行额度：
      // 短章（封面、扉页）能落库靠的是 64KB 固定余量本身。
      expect(
        expectedStoredChapterChars(contentChars: 12),
        12 * 6 + 64 * 1024,
        reason: '上限必须只由正文规模决定',
      );
      // 图片提取失败残留的 base64 内嵌图仍然要挡在库外。
      expect(
        400000 > expectedStoredChapterChars(contentChars: 12),
        isTrue,
        reason: '真正的异常体积不能被放行',
      );
    });
  });

  group('持久化书籍元数据判定', () {
    test('仅复用包含完整内容路径的 EPUB 元数据', () {
      expect(canReuseParsedBookMetadata('EPUB', buildBook()), isTrue);
      expect(canReuseParsedBookMetadata('TXT', buildBook()), isFalse);
      expect(
        canReuseParsedBookMetadata('EPUB', buildBook(secondPath: null)),
        isFalse,
      );
      expect(
        canReuseParsedBookMetadata('EPUB', const ParsedBook(chapters: [])),
        isFalse,
      );
    });

    test('复用包含完整字符偏移的 TXT 元数据', () {
      final book = ParsedBook(
        chapters: const [
          ParsedChapter(
            number: 1,
            title: '正文',
            xhtmlContent: '',
            charCount: 12,
            sourceStartOffset: 0,
            sourceEndOffset: 12,
          ),
        ],
      );

      expect(canReuseParsedBookMetadata('TXT', book), isTrue);
    });
  });

  group('章节标识解析', () {
    test('兼容清单键、内容路径与锚点路径，标题不再当身份', () {
      final book = buildBook();

      expect(resolveParsedChapterIndex(book, 'chapter_1'), 1);
      expect(resolveParsedChapterIndex(book, 'OPS/chapter-2.xhtml'), 1);
      expect(resolveParsedChapterIndex(book, 'OPS/chapter-2.xhtml#section'), 1);
      // 标题是会被解析规则改写的显示文本，同名的卷/章也不止一处，不参与身份解析。
      expect(resolveParsedChapterIndex(book, '第二章'), isNull);
      expect(
        canonicalReaderChapterId(book, 'OPS/chapter-2.xhtml#section'),
        'chapter_1',
      );
    });

    test('清单键就是身份：顺位变化后旧位置键不再命中', () {
      // TXT 清单键按正文起点派生。删掉一个伪标题会让后续章的顺位前移，
      // 但起点不变：按顺位存的旧 id 必须显式解析失败，而不是静默落到别的章。
      final book = ParsedBook(
        chapters: const [
          ParsedChapter(
            number: 1,
            title: '第一章 起',
            xhtmlContent: '',
            charCount: 100,
            chapterKey: 't0',
          ),
          ParsedChapter(
            number: 2,
            title: '第二章 承',
            xhtmlContent: '',
            charCount: 120,
            chapterKey: 't100',
          ),
        ],
      );

      expect(resolveParsedChapterIndex(book, 't100'), 1);
      expect(ReaderChapter.fromParsed(1, book.chapters[1]).id, 't100');
      expect(resolveParsedChapterIndex(book, 'chapter_1'), isNull);
      expect(canonicalReaderChapterId(book, 't0'), 't0');
    });

    test('未知章节标识显式失败返回 null，不静默回退第一章', () {
      final book = buildBook();

      expect(resolveParsedChapterIndex(book, 'legacy-unknown'), isNull);
      expect(
        canonicalReaderChapterId(book, 'legacy-unknown'),
        'legacy-unknown',
      );
      expect(
        resolveParsedChapterIndex(const ParsedBook(chapters: []), 'chapter_0'),
        isNull,
      );
    });
  });

  test('TXT 章节以内联正文直接生成阅读器内容', () {
    const chapter = ParsedChapter(
      number: 1,
      title: 'Chapter 1',
      xhtmlContent: '<p>This is the first chapter.</p>',
      charCount: 28,
    );

    final content = inlineReaderChapterContent(chapter);

    expect(content, isNotNull);
    expect(content!.content, contains('This is the first chapter.'));
    expect(content.wordCount, greaterThan(0));
  });

  test('空内联正文不生成阅读器内容', () {
    const chapter = ParsedChapter(
      number: 1,
      title: '第一章',
      xhtmlContent: '  ',
      charCount: 12,
    );

    expect(inlineReaderChapterContent(chapter), isNull);
  });

  test('TXT 可以按服务端字符偏移提取章节正文', () {
    final bytes = Uint8List.fromList(utf8.encode('前言\r\n第一章\r\n章节正文'));
    final service = TxtParserService();
    final text = service.decodeText(bytes);
    final start = text.indexOf('第一章');

    // 与阅读页取正文同一条链：切片 → 转换，客户端不再自己切章。
    final xhtml = service.textToXhtml(
      service.rawChapterSlice(text, start, text.length),
    );

    expect(xhtml, contains('第一章'));
    expect(xhtml, contains('章节正文'));
  });

  test('TXT 服务端偏移章节生成稳定缓存键', () {
    const chapter = ParsedChapter(
      number: 1,
      title: '第一章',
      xhtmlContent: '',
      charCount: 12,
      sourceStartOffset: 8,
      sourceEndOffset: 20,
    );

    expect(readerChapterCacheKey(chapter), 'txt/8-20@0.xhtml');

    // 剥掉标题行后同一区间的正文内容不同，键必须区分（D-12）
    const stripped = ParsedChapter(
      number: 1,
      title: '第一章',
      xhtmlContent: '',
      charCount: 12,
      sourceStartOffset: 8,
      sourceEndOffset: 20,
      bodyStartOffset: 5,
    );

    expect(readerChapterCacheKey(stripped), 'txt/8-20@5.xhtml');
  });

  test('正文长度按标题行起点折算，与服务端 substring 口径一致', () {
    expect(txtChapterBodyChars(12, 0), 12);
    expect(txtChapterBodyChars(12, 5), 7);
    // 整章只有标题行：正文为空
    expect(txtChapterBodyChars(12, 12), 0);
    expect(txtChapterBodyChars(12, 30), 0);
  });

  test('服务端 TXT 单章正文只在长度与正文区间一致时可用', () {
    // 清单区间 12 字符，其中标题行占 6 字符，正文期望长度为 6
    expect(txtChapterTextMatchesManifestRange('正文内容正文', 6, 6), isTrue);
    // 清单来自另一个 manifest 版本时区间不等，必须回退而不是渲染别章
    expect(txtChapterTextMatchesManifestRange('正文内容正文', 6, 8), isFalse);
    expect(txtChapterTextMatchesManifestRange('正文内容正文', 4, 6), isFalse);
    // 整章只有标题行时正文长度为 0，是合法状态而不是异常
    expect(txtChapterTextMatchesManifestRange('', 0, 0), isTrue);
  });

  test('本地兜底切片按正文起点剥掉标题行', () {
    const rawSlice = '第一章 甲\n正文内容';

    expect(txtChapterBody(rawSlice, 6), '正文内容');
    expect(txtChapterBody(rawSlice, 0), rawSlice);
    // 清单超前于切片时退到空正文，不越界抛错
    expect(txtChapterBody(rawSlice, rawSlice.length + 4), '');
  });
}
