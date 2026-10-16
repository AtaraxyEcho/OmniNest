import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/data/txt_parser_service.dart';
import 'package:omninest/features/reader/presentation/widgets/block_clipper.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_html_parser.dart';

/// TXT 分段与抓取残留屏蔽的回归测试。
///
/// 钉住四件事：零缩进的网文正文按"行即段"分段；定宽硬换行不许被切成碎段；
/// 章尾孤立空行不否定整档；分隔线行与段末字数计数器被屏蔽后仍不改变字符域
/// （`BlockClipper.blockCharCount` 按源空间计数，页窗口与批注偏移都落在这个空间里）。
void main() {
  final parser = TxtParserService();

  /// 每行长度不同的网文正文：一段一行、零缩进、句末挂着抓取站的剩余字数。
  String webNovelBody({int lines = 12, bool withCounter = true}) {
    return <String>[
      for (var index = 0; index < lines; index++)
        '${'叙' * (5 + index * 3)}。${withCounter ? index + 1 : ''}',
    ].join('\n');
  }

  /// 定宽硬换行：每行一样长，段与段之间也没有空行。
  String fixedWidthBody({int lines = 12, int width = 20}) {
    return <String>[
      for (var index = 0; index < lines; index++) '内' * width,
    ].join('\n');
  }

  List<String> paragraphsOf(String xhtml) =>
      RegExp(
        r'<p>([\s\S]*?)</p>',
      ).allMatches(xhtml).map((match) => match.group(1)!).toList();

  int blockChars(String xhtml) => parseBlocks(
    xhtml,
  ).fold(0, (sum, block) => sum + BlockClipper.blockCharCount(block));

  group('分段模式判定', () {
    test('零缩进网文正文按行分段', () {
      final paragraphs = paragraphsOf(parser.textToXhtml(webNovelBody()));

      expect(paragraphs, hasLength(12));
    });

    test('章尾孤立空行不否定整档分段', () {
      // 服务端正文切片带着章末那一个空白行：以前"出现过空行"就退回 Mode W，
      // 整章被塞进一个 <p>，读者看到所有文字堆成一段。
      final paragraphs = paragraphsOf(
        parser.textToXhtml('${webNovelBody()}\n'),
      );

      expect(paragraphs, hasLength(12));
    });

    test('定宽硬换行保持段内连排，不切成碎段', () {
      final paragraphs = paragraphsOf(parser.textToXhtml(fixedWidthBody()));

      expect(paragraphs, hasLength(1));
      expect(paragraphs.single.contains('\n'), isTrue);
    });

    test('空行确实分段时按空行分段', () {
      final text = '${'甲' * 30}\n\n${'乙' * 26}';

      final paragraphs = paragraphsOf(parser.textToXhtml(text));

      expect(paragraphs, hasLength(2));
    });

    test('行首缩进的经典排版仍按行分段', () {
      final text = <String>[
        for (var index = 0; index < 12; index++) '　　${'句' * (6 + index)}。',
      ].join('\n');

      expect(paragraphsOf(parser.textToXhtml(text)), hasLength(12));
    });
  });

  group('抓取残留屏蔽', () {
    test('章题下的分隔线行不进正文', () {
      final text = '------------------------\n${webNovelBody(lines: 10)}';

      final paragraphs = paragraphsOf(parser.textToXhtml(text));

      expect(paragraphs, hasLength(10));
      for (final paragraph in paragraphs) {
        expect(paragraph.trim(), isNot(contains('-')));
      }
    });

    test('段末计数器按章级统计屏蔽，且屏蔽后仍是等长空白', () {
      final source = webNovelBody();

      final xhtml = parser.textToXhtml(source);

      for (final paragraph in paragraphsOf(xhtml)) {
        expect(paragraph.trimRight().endsWith('。'), isTrue, reason: '数字应被剥掉');
      }
      // 屏蔽只改成空白：字符域与源切片同样长，进度与批注偏移不整体漂移。
      expect(blockChars(xhtml), source.length);
    });

    test('行尾数字不是计数器形状时原样保留', () {
      // 前一个字符不是句末标点：这类行尾数字是正文内容，不许吃掉。
      final text = <String>[
        for (var index = 0; index < 12; index++)
          '${'事' * (7 + index)}共${index + 1}',
      ].join('\n');

      final xhtml = parser.textToXhtml(text);

      expect(xhtml, contains('共1'));
      expect(xhtml, contains('共12'));
    });

    test('计数器占比不足时整章不屏蔽', () {
      // 一半行挂计数器不足以判定这是抓取站残留，宁可不剥。
      final mixed = <String>[
        for (var index = 0; index < 6; index++)
          '${'段' * (8 + index)}。${index + 1}',
        for (var index = 0; index < 6; index++) '${'段' * (8 + index)}。',
      ].join('\n');

      final xhtml = parser.textToXhtml(mixed);

      expect(xhtml, contains('。1'));
    });
  });

  group('字符域守恒', () {
    test('带残留的整章转换后源字符总数不变', () {
      final source = '========================\n${webNovelBody(lines: 14)}\n';

      expect(blockChars(parser.textToXhtml(source)), greaterThan(0));
      expect(
        paragraphsOf(
          parser.textToXhtml(source),
        ).fold(0, (sum, paragraph) => sum + paragraph.length),
        source.length,
      );
    });

    test('定宽硬换行的空白结转后仍等于源长度', () {
      final source = fixedWidthBody();

      expect(
        paragraphsOf(
          parser.textToXhtml(source),
        ).fold(0, (sum, paragraph) => sum + paragraph.length),
        source.length,
      );
    });
  });
}
