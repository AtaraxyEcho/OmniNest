import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_block_item.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_html_parser.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_pagination_engine.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 摘要：一块文本只能有一个高度。
///
/// 滚动侧的累积高度表用 `measureBlockHeight`（逐逻辑行、不插段分隔符、按整宽），
/// 而同一块内的 charOffset↔像素插值用共享视觉行结果（合并 painter、插缩进与换行、
/// 引用与列表减内缩）。两套行盒给出两个块高，于是 contentYToCharOffset 先在一张
/// 与实际渲染不符的表里定位块，再在块内用另一套行盒换算偏移——落位误差与
/// 退出记录的偏移都会随章节长度累积。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final settings = ReaderViewSettings(
    fontFamily: 'sans',
    fontSize: 18,
    lineHeight: 1.6,
  );
  const width = 360.0;

  double visualLinesHeight(ContentBlock block, {int blockGlobalOffset = 0}) {
    return ReaderPaginationEngine.measureVisualLines(
      block,
      width,
      settings,
      1,
      blockGlobalOffset: blockGlobalOffset,
    ).fold(0.0, (sum, line) => sum + line.height);
  }

  double measuredHeight(ContentBlock block) =>
      ReaderPaginationEngine.measureBlockHeight(
        block,
        width,
        settings,
        textScale: 1,
      );

  group('块高单一来源', () {
    test('硬换行段落的块高等于其视觉行高之和', () {
      final lines = <String>[
        'alpha beta gamma delta epsilon',
        'zeta eta theta iota kappa',
        'lambda mu nu xi omicron',
        'pi rho sigma tau upsilon',
      ];
      final block = parseBlocks('<p>${lines.join('\n    ')}</p>').single;

      final paragraph = block is ParagraphBlock ? block : null;
      final trailing =
          paragraph == null
              ? 0.0
              : settings.fontSize *
                  settings.paragraphSpacingScaleFor(
                    bookStyle: paragraph.style,
                    hasTrailingSpacing: paragraph.hasTrailingSpacing,
                  );
      expect(
        measuredHeight(block),
        closeTo(visualLinesHeight(block) + trailing, 0.01),
        reason: '高度表与块内插值使用了不同行盒',
      );
    });

    test('引用块块高等于其视觉行高之和加固定内缩留白', () {
      final block =
          parseBlocks(
            '<blockquote>${List<String>.filled(12, 'a b c d e f g h ').join()}</blockquote>',
          ).single;

      // 盒留白按稿子取（外 30/32 + 上下内衬各 4），且必须从同一份常量算：
      // 写死数字的话改了渲染侧常量，这条用例就再也测不出漂移。
      const boxChrome =
          ReaderContentBlockItem.blockquoteOuterTopPadding +
          ReaderContentBlockItem.blockquoteOuterBottomPadding +
          ReaderContentBlockItem.blockquoteInnerVerticalPadding * 2;
      expect(
        measuredHeight(block),
        closeTo(visualLinesHeight(block) + boxChrome, 0.01),
      );
    });

    test('长段落折行数在两处一致（不再一处按逻辑行一处按视觉行）', () {
      final block =
          parseBlocks(
            '<p>${List<String>.filled(6, 'one two three four five six').join(' ')}</p>',
          ).single;
      final visualCount =
          ReaderPaginationEngine.measureVisualLines(
            block,
            width,
            settings,
            1,
            blockGlobalOffset: 0,
          ).length;
      // 逻辑行数：合并前每行一条；渲染与分页都按折行后的视觉行计高。
      final logicalCount = block is ParagraphBlock ? block.lines.length : 0;
      expect(visualCount, greaterThan(logicalCount));
      expect(measuredHeight(block), closeTo(visualLinesHeight(block), 0.01));
    });
  });
}
