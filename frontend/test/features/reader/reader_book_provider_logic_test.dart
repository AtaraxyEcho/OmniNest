import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/application/reader_book_provider.dart';
import 'package:omninest/features/reader/data/txt_parser_service.dart';
import 'package:omninest/features/reader/domain/parsed_book.dart';

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
    test('兼容规范 ID、内容路径、锚点路径和标题', () {
      final book = buildBook();

      expect(resolveParsedChapterIndex(book, 'chapter_1'), 1);
      expect(resolveParsedChapterIndex(book, 'OPS/chapter-2.xhtml'), 1);
      expect(resolveParsedChapterIndex(book, 'OPS/chapter-2.xhtml#section'), 1);
      expect(resolveParsedChapterIndex(book, '第二章'), 1);
      expect(canonicalReaderChapterId(book, '第二章'), 'chapter_1');
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
    final bytes = Uint8List.fromList(
      utf8.encode('Chapter 1\nThis is the first chapter.'),
    );
    final book = TxtParserService().parse(bytes, fileName: 'sample.txt');

    expect(book.chapters, isNotEmpty);
    final content = inlineReaderChapterContent(book.chapters.first);
    expect(content, isNotNull);
    expect(content!.content, contains('This is the first chapter.'));
    expect(content.wordCount, greaterThan(0));
  });

  test('TXT 可以按服务端字符偏移提取章节正文', () {
    final bytes = Uint8List.fromList(utf8.encode('前言\r\n第一章\r\n章节正文'));
    final service = TxtParserService();
    final text = service.decodeText(bytes);
    final start = text.indexOf('第一章');

    final xhtml = service.chapterToXhtml(bytes, start, text.length);

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
