import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:omninest/features/reader/data/epub_parser_service.dart';
import 'package:omninest/features/reader/data/txt_parser_service.dart';
import 'package:omninest/features/reader/presentation/widgets/block_clipper.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_book_stylesheet.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_block_item.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_html_parser.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';
import 'package:xml/xml.dart' as xml;

/// 摘要：对导入后的真书逐章统计「读者实际看到的排版」与「书自己表达的排版」。
///
/// 这一组回答的是开关问题：`跟随原书排版` 打开后，读者看到的字面文本到底变了没有。
/// 它不比较高度或页预算（那是 reader_epub_corpus_test 的职责），只比较**绘制出来的
/// 字符串**：缩进字数、段前留白、对齐、以及源文本里字面全角缩进的去向。
///
/// 语料是本机素材，目录缺失时整组 skip。
/// 跑法：`flutter test test/features/reader/reader_imported_book_typesetting_audit_test.dart`
/// 换目录：`flutter test --dart-define=READER_DIR=D:/Other/Books test/features/reader/reader_imported_book_typesetting_audit_test.dart`
/// 装配规则的等宽文本视图：换行照原样，缩进盒子记成同样字宽的全角空格。
///
/// 真实排版由 `paragraphGapSpans` 给出 span 序列；这里只为把一整块的版面拼成
/// 字符串比对，规则一律以 `paragraphGap` 为准。
String paragraphLineSeparator({
  required bool isFirstLine,
  required bool isNewParagraph,
  required bool previousLineIsEmpty,
  required bool isBlockContinuation,
  required bool startsWithFullWidthIndent,
  int indentChars = defaultFirstLineIndentChars,
  bool isSoftWrap = false,
}) {
  final gap = paragraphGap(
    isFirstLine: isFirstLine,
    isNewParagraph: isNewParagraph,
    previousLineIsEmpty: previousLineIsEmpty,
    isBlockContinuation: isBlockContinuation,
    startsWithFullWidthIndent: startsWithFullWidthIndent,
    indentChars: indentChars,
    isSoftWrap: isSoftWrap,
  );
  return '${gap.newLine ? '\n' : ''}${'　' * gap.indentChars}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const corpusPath = String.fromEnvironment(
    'READER_DIR',
    defaultValue: r'D:/Development/Resource/Reader',
  );
  const maxChaptersPerBook = 12;

  final epubFiles = _findFiles(corpusPath, '.epub');
  final txtFiles = _findFiles(corpusPath, '.txt');

  if (epubFiles.isEmpty && txtFiles.isEmpty) {
    test('语料缺失', () {
      expect(true, isTrue);
    }, skip: '未找到 $corpusPath 下的 .epub/.txt');
    return;
  }

  final readerDefault = ReaderViewSettings(
    fontFamily: 'serif',
    fontSize: 19,
    lineHeight: 1.85,
  );
  final followBook = readerDefault.copyWith(followBookTypesetting: true);

  group('导入真书的排版审计', () {
    final totals = _AuditTotals();

    for (final file in epubFiles) {
      test('EPUB ${_shortName(file.path)}', () async {
        final service = EpubParserService();
        final book = _BookReport(_shortName(file.path), kind: 'EPUB');
        final lease = await service.acquireLease();
        try {
          final hrefs = _spineHrefs(file);
          for (final href in hrefs.take(maxChaptersPerBook)) {
            final chapter = await service.parseChapterFile(file.path, href);
            if (chapter == null || chapter.xhtml.trim().isEmpty) continue;
            book.audit(
              xhtml: chapter.xhtml,
              css: buildChapterStylesheetCss(
                chapter.stylesheetPool,
                chapter.stylesheetRefs,
              ),
              readerDefault: readerDefault,
              followBook: followBook,
            );
          }
        } catch (error) {
          book.failure = '$error';
        } finally {
          lease.release();
          service.releaseArchive();
        }
        book.finish();
        totals.add(book);
        debugPrint(book.render());
      });
    }

    for (final file in txtFiles) {
      test('TXT ${_shortName(file.path)}', () {
        final service = TxtParserService();
        final raw = file.readAsBytesSync();
        final text = service.decodeText(raw);
        final book = _BookReport(_shortName(file.path), kind: 'TXT');
        // 与线上一致：服务端按标题切章，客户端只拿到本章切片。审计取中段
        // 3000 行当一章正文，足够让章级判据（Mode P / Mode W）落在真值上。
        final lines = text.split('\n');
        final start = (lines.length * 0.35).toInt();
        final slice = lines.skip(start).take(3000).join('\n');
        book.audit(
          xhtml: service.textToXhtml(slice),
          css: '',
          readerDefault: readerDefault,
          followBook: followBook,
        );
        book.finish();
        totals.add(book);
        debugPrint(book.render());
      });
    }

    test('汇总', () {
      debugPrint(totals.render());
      expect(totals.charDomainBreaks, 0, reason: '样式表与源文本字面缩进只能改版面，不能改字符总数');
      expect(
        totals.headingCountBreaks,
        0,
        reason: '纯图标题与空锚点标题若整块丢掉，标题层级与章节锚点一起查不到出处',
      );
      expect(totals.missedSplitCount, 0, reason: '段中图之后必须是续行，否则后半句凭空多出一处首行缩进');
      expect(
        totals.sourceMidImageCuts,
        greaterThan(0),
        reason: '闸门采不到"文字—图—文字"的切点，语料或取样口径变了',
      );
    });
  });
}

List<File> _findFiles(String dir, String suffix) {
  final directory = Directory(dir);
  if (!directory.existsSync()) return const [];
  final files =
      directory
          .listSync()
          .whereType<File>()
          .where((file) => file.path.toLowerCase().endsWith(suffix))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return files;
}

String _shortName(String path) => path.split(RegExp(r'[\\/]')).last;

/// spine 顺序的章节 href，与阅读端拿到的章序一致。
List<String> _spineHrefs(File file) {
  final archive = ZipDecoder().decodeBytes(file.readAsBytesSync());
  String? textAt(String path) {
    final entry = archive.findFile(path);
    if (entry == null) return null;
    return utf8.decode(entry.content as List<int>, allowMalformed: true);
  }

  final container = textAt('META-INF/container.xml');
  if (container == null) return const [];
  final opfPath =
      xml.XmlDocument.parse(
        container,
      ).findAllElements('rootfile').first.getAttribute('full-path')!;
  final opf = textAt(opfPath);
  if (opf == null) return const [];
  final document = xml.XmlDocument.parse(opf);
  final directory = _parentOf(opfPath);
  final chapterById = <String, String>{};
  for (final item in document.findAllElements('item')) {
    final id = item.getAttribute('id');
    final href = item.getAttribute('href');
    if (id == null || href == null) continue;
    final mediaType = item.getAttribute('media-type')?.toLowerCase() ?? '';
    if (mediaType == 'application/xhtml+xml' || mediaType == 'text/html') {
      chapterById[id] = _joinPath(directory, href);
    }
  }
  final hrefs = <String>[];
  for (final itemref in document.findAllElements('itemref')) {
    final id = itemref.getAttribute('idref');
    final href = id == null ? null : chapterById[id];
    if (href != null) hrefs.add(href);
  }
  return hrefs;
}

String _parentOf(String path) {
  final index = path.lastIndexOf('/');
  return index < 0 ? '' : path.substring(0, index);
}

String _joinPath(String base, String href) {
  final clean = href.split('#').first.split('?').first;
  final parts = <String>[];
  for (final part in '$base/$clean'.split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (parts.isNotEmpty) parts.removeLast();
      continue;
    }
    parts.add(part);
  }
  return parts.join('/');
}

/// 一块在读者眼里的样子：按渲染侧同一条装配规则拼出绘制文本，再叠上块级留白与对齐。
///
/// 段距与对齐不进字符串，只进高度和 `textAlign`，所以三者一起比才看得出开关真的换了版面。
String paintedBlock(ContentBlock block, ReaderViewSettings settings) {
  if (block is! ParagraphBlock) return '';
  final buffer = StringBuffer();
  for (var i = 0; i < block.lines.length; i++) {
    final line = block.lines[i];
    buffer.write(
      paragraphLineSeparator(
        isFirstLine: i == 0,
        isNewParagraph: line.isNewParagraph,
        previousLineIsEmpty: i > 0 && block.lines[i - 1].spans.isEmpty,
        isBlockContinuation: false,
        startsWithFullWidthIndent: lineStartsWithFullWidthIndent(line.spans),
        indentChars: settings.firstLineIndentChars(line.style),
        isSoftWrap: line.softWrap,
      ),
    );
    buffer.writeAll(line.spans.map((span) => span.text));
  }
  return buffer.toString();
}

/// 这一段在读者眼里占的版面：文字 + 块级留白 + 对齐。
String paintedLayout(ContentBlock block, ReaderViewSettings settings) {
  final align =
      block is ParagraphBlock ? '${settings.paragraphAlign(block.style)}' : '';
  final chrome = ReaderContentBlockItem.blockChromeHeight(block, settings);
  return '${paintedBlock(block, settings)}|$align|${chrome.toStringAsFixed(2)}';
}

/// 一章的字符总数：块模型里的每一个源字符都要在字符域里有一个位置。
int _totalChars(List<ContentBlock> blocks) => blocks.fold<int>(
  0,
  (sum, block) => sum + BlockClipper.blockCharCount(block),
);

/// 源里"文字—（一串）图—文字"的切点数：这些位置解析后必须落成续行。
///
/// 只数 `<p>` 里的图，是因为容器裸文本那条通路（`<div>甲<img/>乙</div>`）的
/// 断点也算续行，会让这个数**只多不少**——闸门取单向：标记数不得少于源切点数。
int _midParagraphImageCuts(String xhtml) {
  final document = html_parser.parse(xhtml);
  var cuts = 0;
  for (final paragraph in document.querySelectorAll('p')) {
    // 引用块、表格单元格、列表与 pre 这几条通路把内联内容摊平成行（图本来就不落块），
    // 数进来会让闸门虚报"漏标"。
    if (_hasAncestorIn(paragraph, const {
      'blockquote',
      'table',
      'ul',
      'ol',
      'pre',
      'figure',
    })) {
      continue;
    }
    // 段落内容压成 T（非空白文本）与 I（带 src 的图）的序列，跳过非正文子树。
    final tokens = <String>[];
    void walk(dom.Node node) {
      if (node is dom.Text) {
        if (node.text.trim().isNotEmpty) tokens.add('T');
        return;
      }
      if (node is! dom.Element) return;
      final tag = node.localName ?? '';
      if (const {'style', 'script', 'template', 'noscript'}.contains(tag)) {
        return;
      }
      if (tag == 'img') {
        final src = node.attributes['src'];
        if (src != null && src.isNotEmpty) tokens.add('I');
        return;
      }
      for (final child in node.nodes) {
        walk(child);
      }
    }

    for (final child in paragraph.nodes) {
      walk(child);
    }
    var index = 0;
    while (index < tokens.length) {
      if (tokens[index] != 'I') {
        index++;
        continue;
      }
      var end = index;
      while (end < tokens.length && tokens[end] == 'I') {
        end++;
      }
      // 相邻多张图只切断一次：两端都有文本才算一个切点。
      if (index > 0 && end < tokens.length) {
        cuts++;
      }
      index = end;
    }
  }
  return cuts;
}

/// 源 XHTML 里**块级**标题按层级计数。
///
/// 引用、表格、列表、`pre` 与 figure 里的标题走各自的摊平通路，本来就不产出
/// HeadingBlock，数进来只会把"没有丢失"报成"丢失"。
Map<String, int> _sourceBlockHeadingLevels(String xhtml) {
  final document = html_parser.parse(xhtml);
  final levels = <String, int>{};
  for (final heading in document.querySelectorAll('h1,h2,h3,h4,h5,h6')) {
    if (_hasAncestorIn(heading, const {
      'blockquote',
      'table',
      'ul',
      'ol',
      'pre',
      'figure',
    })) {
      continue;
    }
    final key = (heading.localName ?? 'h6').toLowerCase();
    levels[key] = (levels[key] ?? 0) + 1;
  }
  return levels;
}

bool _hasAncestorIn(dom.Element element, Set<String> tags) {
  dom.Node? parent = element.parent;
  while (parent is dom.Element) {
    if (tags.contains(parent.localName)) {
      return true;
    }
    parent = parent.parent;
  }
  return false;
}

/// 源 XHTML 里每个块级段落的**字面**行首全角缩进字数（剥掉标签后取行首）。
///
/// 这是"原书怎么写的"唯一一手证据：书常用字面 `　　` 而不是 CSS 表达缩进。
List<int> _sourceLiteralIndents(String xhtml) {
  final body =
      RegExp(r'<body[^>]*>([\s\S]*?)</body>').firstMatch(xhtml)?.group(1) ??
      xhtml;
  final stripped = body
      .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<[^>]+>'), '');
  final decoded = stripped
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
  final indents = <int>[];
  for (final line in decoded.split('\n')) {
    if (line.trim().isEmpty) continue;
    var full = 0;
    for (final unit in line.runes) {
      if (unit == 0x3000) {
        full++;
      } else {
        break;
      }
    }
    indents.add(full);
  }
  return indents;
}

class _BookReport {
  _BookReport(this.name, {required this.kind});

  final String name;

  /// 载体类型：EPUB 有样式表，TXT 只有源文本的字面形状，两者的失效原因不同。
  final String kind;

  /// 整章审计被中断的原因（畸形归档、超限压缩比等），null 表示跑完了。
  String? failure;

  int chapters = 0;
  int blocks = 0;
  int paragraphs = 0;
  int headings = 0;
  int dividers = 0;
  int images = 0;
  int quotes = 0;
  int lists = 0;
  int tables = 0;
  int cssChars = 0;
  int rules = 0;
  int chaptersWithoutCss = 0;

  /// 书通过 CSS 表达过的缩进/段距/对齐取值分布。
  final Map<String, int> cssIndentValues = {};
  final Map<String, int> cssSpacingValues = {};
  final Map<String, int> cssAlignValues = {};
  int cssExpressedIndentParagraphs = 0;

  /// 源文本里字面全角缩进的分布（按行统计）。
  final Map<String, int> sourceIndentValues = {};
  int sourceIndentedLines = 0;
  int sourceLines = 0;

  /// 开关可见性：打开后绘制文本真的不同的段落数。
  int switchDiffersParagraphs = 0;

  /// 版面可见性：文字、块级留白与对齐三者合起来比，才算开关换了没有。
  int layoutDiffersParagraphs = 0;
  double chromeDefaultSum = 0;
  double chromeFollowSum = 0;

  /// 缩进表达的出处：样式表（含祖先继承）/ 源文本字面 / 书完全没说。
  int literalIndentParagraphs = 0;
  int unexpressedIndentParagraphs = 0;
  final Map<String, int> literalIndentValues = {};

  /// 标题层级：块型里的 level 分布，与源 XHTML 里 h1..h6 的出现次数。
  final Map<String, int> headingLevelValues = {};
  final Map<String, int> headingAlignValues = {};
  final Map<String, int> sourceHeadingTags = {};

  /// 字符域守卫的违约章数与样本。
  int charDomainBreaks = 0;
  final List<String> charDomainSamples = [];

  /// 块级标题逐层级不相等的次数（T8 的差分闸门）。
  int headingCountBreaks = 0;
  final List<String> headingSamples = [];

  /// 源里"文字—图—文字"的切点数，解析结果里标了续行的切点数，以及漏标数。
  int sourceMidImageCuts = 0;
  int markedSplitCount = 0;
  int missedSplitCount = 0;
  final List<String> missedSplitSamples = [];

  /// 与"原书怎么写"的偏离：读者看到的行首缩进字数 vs 源字面缩进字数。
  final Map<String, int> defaultRenderedIndentValues = {};
  final Map<String, int> followRenderedIndentValues = {};

  /// 空行/换行形状：源里空行分段、软换行续行、`<br>` 行的规模。
  int softWrapLines = 0;
  int newParagraphLines = 0;
  int trailingSpacingBlocks = 0;
  int multiLineParagraphs = 0;
  int totalLines = 0;

  /// 字号/字族：白名单外，书表达过的 font-size 规则数（只统计，不采纳）。
  int fontSizeRules = 0;

  void audit({
    required String xhtml,
    required String css,
    required ReaderViewSettings readerDefault,
    required ReaderViewSettings followBook,
  }) {
    chapters++;
    cssChars += css.length;
    if (css.isEmpty) {
      chaptersWithoutCss++;
    } else {
      final sheet = BookStyleSheet.parse(css);
      rules += sheet.ruleCount;
      fontSizeRules +=
          RegExp('font-size', caseSensitive: false).allMatches(css).length;
    }

    final blocks = parseBlocks(xhtml, css: css);
    // 字符域守卫：样式表与源文本字面缩进都只改「怎么摆」，不能改「有多少字」。
    // 同一份正文带不带样式，字符总数必须逐章相等，否则进度、批注与页区间会因为
    // 一本书有没有 CSS 而落到不同的字上。
    final bareChars = _totalChars(parseBlocks(xhtml));
    final styledChars = _totalChars(blocks);
    if (bareChars != styledChars) {
      charDomainBreaks++;
      if (charDomainSamples.length < 6) {
        charDomainSamples.add('带样式 $styledChars 字、无样式 $bareChars 字');
      }
    }
    this.blocks += blocks.length;
    // 标题计数差分：卷首艺术字标题（`<h1><img/></h1>`）与只做目录跳转的空标题
    // 都没有正文文字，按文字判空会整块丢掉——层级、锚点连同那张图一起消失。
    // 逐层级比：总数相等也可能是一层少一层多互相抵掉。
    final sourceHeadingLevels = _sourceBlockHeadingLevels(xhtml);
    final blockHeadingLevels = <String, int>{};
    for (final block in blocks.whereType<HeadingBlock>()) {
      final key = 'h${block.level}';
      blockHeadingLevels[key] = (blockHeadingLevels[key] ?? 0) + 1;
    }
    for (final level in <String>{
      ...sourceHeadingLevels.keys,
      ...blockHeadingLevels.keys,
    }) {
      final source = sourceHeadingLevels[level] ?? 0;
      final derived = blockHeadingLevels[level] ?? 0;
      if (source != derived) {
        headingCountBreaks++;
        if (headingSamples.length < 6) {
          headingSamples.add('$level 源 $source，块 $derived');
        }
      }
    }
    // 断言只看一个方向：源里"文字—图—文字"的切点数，必须不多于解析结果里
    // 紧跟图且首行标了续行的段落数。夹在两个 `<p>` 之间的独立插图本来就起新段，
    // 不该被标成续行，所以不能拿"图前后都是段落"当判据。
    final sourceCuts = _midParagraphImageCuts(xhtml);
    sourceMidImageCuts += sourceCuts;
    var markedContinuations = 0;
    for (var index = 1; index < blocks.length; index++) {
      final block = blocks[index];
      if (block is! ParagraphBlock || blocks[index - 1] is! ImageBlock) {
        continue;
      }
      if (block.lines.isNotEmpty && block.lines.first.softWrap) {
        markedContinuations++;
      }
    }
    markedSplitCount += markedContinuations;
    if (markedContinuations < sourceCuts) {
      missedSplitCount += sourceCuts - markedContinuations;
      if (missedSplitSamples.length < 4) {
        missedSplitSamples.add('源切点 $sourceCuts，标了续行 $markedContinuations');
      }
    }
    for (final block in blocks) {
      switch (block) {
        case HeadingBlock(:final level, :final align):
          headings++;
          headingLevelValues['h$level'] =
              (headingLevelValues['h$level'] ?? 0) + 1;
          // 标题这条通路在修复前根本不读样式表，所以这份计数就是它的回归闸门。
          if (align != null) {
            headingAlignValues[align.name] =
                (headingAlignValues[align.name] ?? 0) + 1;
          }
        case DividerBlock():
          dividers++;
        case ImageBlock():
          images++;
        case BlockquoteBlock():
          quotes++;
        case ListBlock():
          lists++;
        case TableBlock():
          tables++;
        case ParagraphBlock():
          paragraphs++;
      }
      if (block is! ParagraphBlock) continue;
      totalLines += block.lines.length;
      if (block.lines.length > 1) multiLineParagraphs++;
      for (final line in block.lines) {
        if (line.softWrap) softWrapLines++;
        if (line.isNewParagraph) newParagraphLines++;
      }
      if (block.hasTrailingSpacing) trailingSpacingBlocks++;

      final style = block.style;
      final spacing = style?.paragraphSpacingScale;
      if (spacing != null) {
        cssSpacingValues[spacing.toStringAsFixed(2)] =
            (cssSpacingValues[spacing.toStringAsFixed(2)] ?? 0) + 1;
      }
      final align = style?.textAlign;
      if (align != null) {
        cssAlignValues['$align'] = (cssAlignValues['$align'] ?? 0) + 1;
      }

      final defaultPainted = paintedBlock(block, readerDefault);
      final followPainted = paintedBlock(block, followBook);
      if (defaultPainted != followPainted) {
        switchDiffersParagraphs++;
      }
      if (paintedLayout(block, readerDefault) !=
          paintedLayout(block, followBook)) {
        layoutDiffersParagraphs++;
      }
      // 书的表达有两个出处：块上的样式来自样式表（含祖先继承），行上那份在块上
      // 没有缩进表达时只可能是源文本的字面全角缩进。
      final lineIndent = block.lines.isEmpty ? null : block.lines.first.style;
      if (block.style?.firstLineIndentChars != null) {
        cssExpressedIndentParagraphs++;
        cssIndentValues['${block.style!.firstLineIndentChars}'] =
            (cssIndentValues['${block.style!.firstLineIndentChars}'] ?? 0) + 1;
      } else if (lineIndent?.firstLineIndentChars != null) {
        literalIndentParagraphs++;
        literalIndentValues['${lineIndent!.firstLineIndentChars}'] =
            (literalIndentValues['${lineIndent.firstLineIndentChars}'] ?? 0) +
            1;
      } else {
        unexpressedIndentParagraphs++;
      }
      defaultRenderedIndentValues[_leadingFullWidthRuns(defaultPainted)] =
          (defaultRenderedIndentValues[_leadingFullWidthRuns(defaultPainted)] ??
              0) +
          1;
      followRenderedIndentValues[_leadingFullWidthRuns(followPainted)] =
          (followRenderedIndentValues[_leadingFullWidthRuns(followPainted)] ??
              0) +
          1;
      chromeDefaultSum += ReaderContentBlockItem.blockChromeHeight(
        block,
        readerDefault,
      );
      chromeFollowSum += ReaderContentBlockItem.blockChromeHeight(
        block,
        followBook,
      );
    }

    final indents = _sourceLiteralIndents(xhtml);
    for (final match in RegExp(
      r'<(h[1-6])\b',
      caseSensitive: false,
    ).allMatches(xhtml)) {
      final tag = match.group(1)!.toLowerCase();
      sourceHeadingTags[tag] = (sourceHeadingTags[tag] ?? 0) + 1;
    }
    sourceLines += indents.length;
    for (final indent in indents) {
      if (indent > 0) sourceIndentedLines++;
      sourceIndentValues['$indent'] = (sourceIndentValues['$indent'] ?? 0) + 1;
    }
  }

  static String _leadingFullWidthRuns(String painted) {
    var count = 0;
    for (final unit in painted.runes) {
      if (unit == 0x3000) {
        count++;
      } else {
        break;
      }
    }
    return '$count';
  }

  void finish() {}

  String render() {
    final pct =
        paragraphs == 0
            ? 0
            : (switchDiffersParagraphs * 100 / paragraphs).round();
    final layoutPct =
        paragraphs == 0
            ? 0
            : (layoutDiffersParagraphs * 100 / paragraphs).round();
    final lines = <String>[
      '── $name ──',
      if (failure != null) '  审计中断：$failure',
      '  章 $chapters｜块 $blocks（段落 $paragraphs、标题 $headings、引用 $quotes、列表 $lists、表格 $tables、图 $images、分隔线 $dividers）',
      '  样式表：$cssChars 字符/章均 ${chapters == 0 ? 0 : (cssChars / chapters).round()}，规则 $rules，无样式表章 $chaptersWithoutCss，声明过 font-size $fontSizeRules 处',
      '  缩进出处：样式表 $cssExpressedIndentParagraphs（$cssIndentValues）、源字面 $literalIndentParagraphs（$literalIndentValues）、书没说 $unexpressedIndentParagraphs',
      '  书经 CSS 表达段距 取值 $cssSpacingValues｜对齐 $cssAlignValues',
      '  源字面全角缩进行 $sourceIndentedLines/$sourceLines，分布 $sourceIndentValues',
      '  开关打开后文字不同的段落 $switchDiffersParagraphs（$pct%）｜版面不同的段落 $layoutDiffersParagraphs（$layoutPct%）',
      '  块级留白合计：关闭档 ${chromeDefaultSum.toStringAsFixed(0)}px，跟随档 ${chromeFollowSum.toStringAsFixed(0)}px',
      '  读者看到的行首缩进（关闭档）$defaultRenderedIndentValues',
      '  读者看到的行首缩进（跟随档）$followRenderedIndentValues',
      '  标题层级：源 $sourceHeadingTags → 块 $headingLevelValues，其中书表达过对齐的 $headingAlignValues',
      '  字符域：带样式与无样式字符总数不等的章 $charDomainBreaks，样本 $charDomainSamples',
      '  标题层级：源与块逐层不等的次数 $headingCountBreaks，样本 $headingSamples',
      '  段中图切点：源 $sourceMidImageCuts 处，解析后标了续行 $markedSplitCount 处，漏标 $missedSplitCount，样本 $missedSplitSamples',
      '  形状：多行段落 $multiLineParagraphs，总逻辑行 $totalLines，软换行续行 $softWrapLines，段首行 $newParagraphLines，`<br><br>` 段距信号 $trailingSpacingBlocks',
    ];
    return lines.join('\n');
  }
}

class _AuditTotals {
  _AuditTotals({this.label = '合计'});

  final String label;

  int chapters = 0;
  int paragraphs = 0;
  int headings = 0;
  int switchDiffers = 0;
  int layoutDiffers = 0;
  int cssExpressedIndent = 0;
  int literalIndent = 0;
  int unexpressedIndent = 0;
  int sourceIndentedLines = 0;
  int sourceLines = 0;
  int chaptersWithoutCss = 0;
  int charDomainBreaks = 0;
  int headingCountBreaks = 0;
  int sourceMidImageCuts = 0;
  int markedSplitCount = 0;
  int missedSplitCount = 0;
  double chromeDefaultSum = 0;
  double chromeFollowSum = 0;
  final List<String> failures = [];
  final Map<String, int> sourceIndentValues = {};
  final Map<String, int> defaultRenderedIndentValues = {};
  final Map<String, int> followRenderedIndentValues = {};
  final Map<String, int> headingLevelValues = {};
  final Map<String, int> headingAlignValues = {};
  final Map<String, int> sourceHeadingTags = {};
  final Map<String, _AuditTotals> byKind = {};

  void add(_BookReport book) {
    if (book.failure != null) {
      failures.add('${book.name}：${book.failure}');
    }
    chapters += book.chapters;
    paragraphs += book.paragraphs;
    headings += book.headings;
    switchDiffers += book.switchDiffersParagraphs;
    layoutDiffers += book.layoutDiffersParagraphs;
    cssExpressedIndent += book.cssExpressedIndentParagraphs;
    literalIndent += book.literalIndentParagraphs;
    unexpressedIndent += book.unexpressedIndentParagraphs;
    sourceIndentedLines += book.sourceIndentedLines;
    sourceLines += book.sourceLines;
    chaptersWithoutCss += book.chaptersWithoutCss;
    charDomainBreaks += book.charDomainBreaks;
    headingCountBreaks += book.headingCountBreaks;
    sourceMidImageCuts += book.sourceMidImageCuts;
    markedSplitCount += book.markedSplitCount;
    missedSplitCount += book.missedSplitCount;
    chromeDefaultSum += book.chromeDefaultSum;
    chromeFollowSum += book.chromeFollowSum;
    _merge(sourceIndentValues, book.sourceIndentValues);
    _merge(defaultRenderedIndentValues, book.defaultRenderedIndentValues);
    _merge(followRenderedIndentValues, book.followRenderedIndentValues);
    _merge(headingLevelValues, book.headingLevelValues);
    _merge(headingAlignValues, book.headingAlignValues);
    _merge(sourceHeadingTags, book.sourceHeadingTags);
    byKind
        .putIfAbsent(book.kind, () => _AuditTotals(label: book.kind))
        .addBook(book);
  }

  /// 只累加计数、不再按载体分流（分组那一层）。
  void addBook(_BookReport book) {
    chapters += book.chapters;
    paragraphs += book.paragraphs;
    headings += book.headings;
    switchDiffers += book.switchDiffersParagraphs;
    layoutDiffers += book.layoutDiffersParagraphs;
    cssExpressedIndent += book.cssExpressedIndentParagraphs;
    literalIndent += book.literalIndentParagraphs;
    unexpressedIndent += book.unexpressedIndentParagraphs;
    sourceIndentedLines += book.sourceIndentedLines;
    sourceLines += book.sourceLines;
    chaptersWithoutCss += book.chaptersWithoutCss;
    charDomainBreaks += book.charDomainBreaks;
    headingCountBreaks += book.headingCountBreaks;
    sourceMidImageCuts += book.sourceMidImageCuts;
    markedSplitCount += book.markedSplitCount;
    missedSplitCount += book.missedSplitCount;
    chromeDefaultSum += book.chromeDefaultSum;
    chromeFollowSum += book.chromeFollowSum;
    _merge(sourceIndentValues, book.sourceIndentValues);
    _merge(defaultRenderedIndentValues, book.defaultRenderedIndentValues);
    _merge(followRenderedIndentValues, book.followRenderedIndentValues);
    _merge(headingLevelValues, book.headingLevelValues);
    _merge(headingAlignValues, book.headingAlignValues);
    _merge(sourceHeadingTags, book.sourceHeadingTags);
  }

  static void _merge(Map<String, int> target, Map<String, int> source) {
    for (final entry in source.entries) {
      target[entry.key] = (target[entry.key] ?? 0) + entry.value;
    }
  }

  int _pct(int value) =>
      paragraphs == 0 ? 0 : (value * 100 / paragraphs).round();

  String render() {
    return [
      '════ $label ════',
      '章 $chapters｜段落 $paragraphs｜标题块 $headings｜无样式表章 $chaptersWithoutCss',
      '缩进出处：样式表 $cssExpressedIndent（${_pct(cssExpressedIndent)}%）、'
          '源字面 $literalIndent、书没说 $unexpressedIndent',
      '源字面全角缩进行 $sourceIndentedLines/$sourceLines，分布 $sourceIndentValues',
      '开关打开后：文字变化 $switchDiffers（${_pct(switchDiffers)}%）、'
          '版面变化 $layoutDiffers（${_pct(layoutDiffers)}%）',
      '块级留白合计：关闭档 ${chromeDefaultSum.toStringAsFixed(0)}px → '
          '跟随档 ${chromeFollowSum.toStringAsFixed(0)}px',
      '关闭档行首缩进分布 $defaultRenderedIndentValues',
      '跟随档行首缩进分布 $followRenderedIndentValues',
      '标题层级：源 $sourceHeadingTags → 块 $headingLevelValues，书表达过对齐的 $headingAlignValues',
      '字符域：带样式与无样式字符总数不等的章 $charDomainBreaks',
      '标题层级：源与块逐层不等的次数 $headingCountBreaks',
      '段中图切点：源 $sourceMidImageCuts 处，标了续行 $markedSplitCount 处，漏标 $missedSplitCount',
      if (failures.isNotEmpty) '审计中断的书 $failures',
      for (final group in byKind.values) group.render(),
    ].join('\n');
  }
}
