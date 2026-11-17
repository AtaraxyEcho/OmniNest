import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/data/txt_parser_service.dart';
import 'package:omninest/features/reader/presentation/widgets/block_clipper.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_block_item.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_html_parser.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 段内硬换行连排与字符记账回归测试（D-16 / D-17 / N-09）。
///
/// 核心不变式：`BlockClipper.blockCharCount` 统计的是**源文本空间**
/// （可绘制字符 + 行首折叠字符），因此分页前缀表、页内裁剪与批注偏移
/// 都落在同一个空间里；源文本中的每个字符既不丢也不重。
void main() {
  List<ParagraphBlock> paragraphsOf(List<ContentBlock> blocks) =>
      blocks.whereType<ParagraphBlock>().toList();

  String paintedOf(LineData line) => line.spans.map((span) => span.text).join();

  int blockChars(List<ContentBlock> blocks) =>
      blocks.fold(0, (sum, block) => sum + BlockClipper.blockCharCount(block));

  group('硬换行连排', () {
    test('单换行连排，空行分段并补缩进', () {
      const html = '<p>第一行正文\n  第二行正文\n\n  第三行正文</p>';

      // 空行是作者留在正文里的段落边界：连排到底会让开关关掉时段落黏成一块，
      // 读者既看不到留白也看不到缩进，等于"这个开关什么也没改"。
      // 段距只存在于块与块之间，所以边界处切成两块，第三段那一行照旧补缩进。
      final blocks = paragraphsOf(parseBlocks(html));
      expect(blocks, hasLength(2), reason: '空行分段必须在边界切块');
      final lines = [for (final block in blocks) ...block.lines];

      expect(lines, hasLength(3));
      expect(lines.first.softWrap, isFalse);
      // 单个换行是段内换行：连排，不补换行符也不补缩进。
      expect(lines[1].softWrap, isTrue);
      expect(lines[2].softWrap, isFalse, reason: '空行之后的段落是新的段首行');
      for (final line in lines) {
        expect(paintedOf(line).contains('\n'), isFalse);
        expect(paintedOf(line), paintedOf(line).trim());
      }

      // 作者留的那一行白记在**前一段之后**（额度只花一份），折算用读者的行高。
      expect(blocks.first.style?.paragraphBlankGapLines, 1);
      expect(
        blocks[1].style?.paragraphBlankGapLines,
        isNull,
        reason: '这一段之前的白已经记给前一块，不能再当它的段后距',
      );
      final reader = ReaderViewSettings(fontSize: 20, lineHeight: 1.8);
      final follow = reader.copyWith(followBookTypesetting: true);
      expect(
        ReaderContentBlockItem.blockLeadingChrome(blocks.first, follow),
        closeTo(20 * 1.8, 0.001),
      );
      expect(
        ReaderContentBlockItem.blockChromeHeight(blocks.first, reader),
        0.0,
        reason: '关掉开关的读者不因为一本书用不用空行分段而多出留白',
      );
    });

    test('容器直属裸文本与 <p> 走同一条折叠规则', () {
      // PG 语料的许可页把整段文字直接写在 <div> 里，源码每约 35 字断一行。
      // 这条路径以前不过 _foldIntoLines：换行原样留在可绘制文本里，一行只剩十几个
      // 字符的锯齿版面；页尾裁剪落在换行之后时还要多折一行空行，渲染比引擎分配的高
      // 出一整行（真书语料里西遊记每章几页）。
      const source =
          'so the Foundation\n  can copy and distribute it\n  in the United States';

      final paragraph = paragraphsOf(parseBlocks('<div>$source</div>')).single;

      expect(paragraph.lines, hasLength(3));
      expect(paragraph.lines.first.softWrap, isFalse);
      for (final line in paragraph.lines.skip(1)) {
        expect(line.softWrap, isTrue);
      }
      for (final line in paragraph.lines) {
        expect(paintedOf(line).contains('\n'), isFalse, reason: '换行不能留在可绘制文本里');
      }
      expect(blockChars([paragraph]), source.length, reason: '折叠量必须留在源字符空间');
    });

    test('源字符总数守恒', () {
      const source = '　　第一行正文\n  第二行正文\n\n　　第三行正文';

      final blocks = parseBlocks('<p>$source</p>');

      expect(blockChars(blocks), source.length);
    });

    test('英文硬换行保留词间空格且长度仍守恒', () {
      const source = 'hello\n  world';

      final paragraph = paragraphsOf(parseBlocks('<p>$source</p>')).single;

      expect(paintedOf(paragraph.lines[0]), 'hello');
      expect(paintedOf(paragraph.lines[1]), ' world');
      expect(blockChars([paragraph]), source.length);
    });

    test('CJK 硬换行不补空格', () {
      const source = '天地玄黄\n  宇宙洪荒';

      final paragraph = paragraphsOf(parseBlocks('<p>$source</p>')).single;

      expect(paragraph.lines.map(paintedOf).join(), '天地玄黄宇宙洪荒');
      expect(blockChars([paragraph]), source.length);
    });

    test('相邻 br 之后仍按源空间计数', () {
      const html = '<p>甲<br><br>乙</p>';

      final paragraph = paragraphsOf(parseBlocks(html)).single;

      expect(paintedOf(paragraph.lines.first), '甲');
      expect(paintedOf(paragraph.lines.last), '乙');
      expect(paragraph.lines.last.collapsedChars, greaterThanOrEqualTo(2));
      expect(paragraph.hasTrailingSpacing, isTrue);
    });
  });

  group('切块与页裁剪的字符空间', () {
    test('长连排段切块后总字符数不变，且块边界不伪装成段首', () {
      final source = List.generate(
        200,
        (index) =>
            '第'
            '$index'
            '行正文内容',
      ).join('\n  ');

      final paragraphs = paragraphsOf(parseBlocks('<p>$source</p>'));

      expect(paragraphs.length, greaterThan(1), reason: '分批防线必须生效');
      expect(
        paragraphs.fold(
          0,
          (sum, block) => sum + BlockClipper.blockCharCount(block),
        ),
        source.length,
      );
      for (final block in paragraphs.skip(1)) {
        expect(
          block.lines.first.softWrap,
          isTrue,
          reason: '切块边界落在段内续行时必须仍是续行，否则会被补出首行缩进',
        );
      }
    });

    test('页内裁剪不丢字不重字', () {
      const source = '第一行正文\n  第二行正文\n  第三行正文';
      final blocks = parseBlocks('<p>$source</p>');

      final clipped = BlockClipper.clipBlocksByCharRange(blocks, 1, 4);

      expect(blockChars(clipped), 3);
      final painted =
          clipped
              .whereType<ParagraphBlock>()
              .expand((block) => block.lines)
              .map(paintedOf)
              .join();
      expect(painted, '一行正');
    });

    test('在分页可请求的边界上，裁剪长度始终等于请求长度', () {
      const source = '　　甲一行\n  乙二行\n  丙三行';
      final blocks = parseBlocks('<p>$source</p>');
      final lines =
          blocks
              .whereType<ParagraphBlock>()
              .expand((block) => block.lines)
              .toList();

      // 每行的源窗口与其中的可绘制子窗口。
      final windows = <List<int>>[];
      var blockStart = 0;
      for (final line in lines) {
        final paintedStart = blockStart + line.collapsedChars;
        windows.add([
          blockStart,
          blockStart + line.sourceChars,
          paintedStart,
          paintedStart + line.paintedChars,
        ]);
        blockStart += line.sourceChars;
      }

      int paintedInside(int start, int end) {
        var total = 0;
        for (final window in windows) {
          final overlap =
              (window[3] < end ? window[3] : end) -
              (window[2] > start ? window[2] : start);
          if (overlap > 0) {
            total += overlap;
          }
        }
        return total;
      }

      // 分页引擎只在可绘制字符边界上请求区间，且请求区间必然含可绘制内容；
      // 完全落在折叠空白里的区间不可能出现，不在本不变式的范围内。
      final boundaries = <int>{};
      for (final window in windows) {
        for (var i = window[2]; i <= window[3]; i++) {
          boundaries.add(i);
        }
      }
      final positions = boundaries.toList()..sort();

      var checked = 0;
      for (var a = 0; a < positions.length; a++) {
        for (var b = a + 1; b < positions.length; b++) {
          final start = positions[a];
          final end = positions[b];
          if (paintedInside(start, end) <= 0) {
            continue;
          }
          checked++;
          final clipped = BlockClipper.clipBlocksByCharRange(
            blocks,
            start,
            end,
          );
          expect(
            blockChars(clipped),
            end - start,
            reason: '裁剪区间 [$start,$end) 的字符数必须等于请求长度',
          );
        }
      }
      expect(checked, greaterThan(10), reason: '不变式必须真的被覆盖到，不能因区间过滤而空转');
    });
  });

  group('TXT 链路的偏移语义', () {
    test('TXT 章文转换后块字符数等于切片长度', () {
      const text = '　　第一行正文内容\n　　第二行正文内容\n　　第三行正文内容\n';
      final parser = TxtParserService();

      final xhtml = parser.textToXhtml(text);
      final blocks = parseBlocks(xhtml);

      // 每个源换行都是一个段落边界，字符不能凭空消失。
      expect(blockChars(blocks), text.length);
    });

    test('TXT 硬换行段落被连排后长度仍等于切片', () {
      final source = List.generate(
        30,
        (index) =>
            '无缩进的硬换行正文'
            '$index',
      ).join('\n');
      final parser = TxtParserService();

      final xhtml = parser.textToXhtml(source);
      final blocks = parseBlocks(xhtml);

      expect(blockChars(blocks), source.length);
    });
  });
}
