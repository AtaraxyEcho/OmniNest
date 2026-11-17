import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/widgets/block_clipper.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_html_parser.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_pagination_engine.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 摘要：钉住"全链路只有一套字符坐标系"。
///
/// 源文本里存在但不可绘制的空白（行首缩进、被连排吞掉的换行串）必须计入
/// 页与页之间的字符区间，否则翻页窗口按可绘制长度切，落到裁剪器（它按源
/// 文本空间解释入参）就会丢字或重字；滚动侧同一偏移又按源空间解释，
/// 于是同一个 charOffset 在两种模式指向不同文本。英文源文本常硬换行，
/// 每行都贡献折叠量，偏差按整页级累积——这正是"英文书进度丢失"的签名。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final settings = ReaderViewSettings(
    fontFamily: 'sans',
    fontSize: 18,
    lineHeight: 1.6,
  );

  // 硬换行 + 行首缩进的英文段落：解析后每个续行的 collapsedChars > 0。
  List<ContentBlock> hardWrappedBlocks() {
    final lines = <String>[
      'alpha beta gamma delta',
      'epsilon zeta eta theta',
      'iota kappa lambda mu',
      'nu xi omicron pi rho',
      'sigma tau upsilon phi chi',
      'psi omega alpha beta',
    ];
    return parseBlocks('<p>${lines.join('\n    ')}</p>');
  }

  String paintedTextOf(List<ContentBlock> blocks) {
    final buffer = StringBuffer();
    for (final block in blocks) {
      if (block is ParagraphBlock) {
        for (final line in block.lines) {
          for (final span in line.spans) {
            buffer.write(span.text);
          }
        }
      } else if (block is HeadingBlock) {
        buffer.write(block.text);
      }
    }
    return buffer.toString();
  }

  int clipperTotal(List<ContentBlock> blocks) =>
      blocks.fold(0, (sum, block) => sum + BlockClipper.blockCharCount(block));

  /// 从 0 起按页高推进到章末，返回页切片序列。
  List<PageSlice> tile(List<ContentBlock> blocks) {
    final slices = <PageSlice>[];
    var cursor = 0;
    for (var guard = 0; guard < 200; guard++) {
      final slice = ReaderPaginationEngine.computePage(
        blocks,
        180,
        120,
        settings,
        cursor,
      );
      if (slice == null) break;
      if (slice.endCharOffset <= slice.startCharOffset) break;
      slices.add(slice);
      cursor = slice.endCharOffset;
    }
    return slices;
  }

  group('字符坐标系一致性', () {
    test('夹具确实产生折叠字符（源空间长度大于可绘制长度）', () {
      final blocks = hardWrappedBlocks();
      final paragraph = blocks.whereType<ParagraphBlock>().single;
      final collapsed = paragraph.lines.fold<int>(
        0,
        (sum, line) => sum + line.collapsedChars,
      );
      expect(collapsed, greaterThan(0), reason: '夹具没有产生软换行折叠空白');
      expect(clipperTotal(blocks), greaterThan(paintedTextOf(blocks).length));
    });

    test('翻页推进的页区间必须覆盖到源空间章末', () {
      final blocks = hardWrappedBlocks();
      final slices = tile(blocks);
      expect(slices, isNotEmpty);
      expect(slices.first.startCharOffset, 0);
      // 引擎若按可绘制长度计总长，最后一页会提前结束，尾部字符永不可达。
      expect(slices.last.endCharOffset, clipperTotal(blocks));
    });

    test('页与页首尾相接，不重叠也不留缝', () {
      final blocks = hardWrappedBlocks();
      final slices = tile(blocks);
      for (var i = 1; i < slices.length; i++) {
        expect(
          slices[i].startCharOffset,
          slices[i - 1].endCharOffset,
          reason: '第 $i 页起点与上一页终点不连续',
        );
      }
    });

    test('逐页裁剪拼接后与整章可绘制文本完全一致', () {
      final blocks = hardWrappedBlocks();
      final slices = tile(blocks);
      final buffer = StringBuffer();
      for (final slice in slices) {
        buffer.write(
          paintedTextOf(
            BlockClipper.clipBlocksByCharRange(
              blocks,
              slice.startCharOffset,
              slice.endCharOffset,
            ),
          ),
        );
      }
      expect(buffer.toString(), paintedTextOf(blocks));
    });

    test('共享视觉行测量器收到的块前缀与源空间一致', () {
      final blocks = hardWrappedBlocks();
      final paragraph = blocks.single;
      final lineCount = (paragraph as ParagraphBlock).lines.length;
      // 以源空间块首为基准：全局偏移必须是源索引，测量器内部按
      // charAccum += painted + collapsed 累加（text_layout:194）。
      final lines = ReaderPaginationEngine.measureVisualLines(
        paragraph,
        180,
        settings,
        1,
        blockGlobalOffset: 0,
      );
      expect(lines.length, greaterThan(1));
      expect(lines.first.globalStart, greaterThanOrEqualTo(0));
      expect(lines.last.globalEnd, lessThanOrEqualTo(clipperTotal(blocks)));
      for (var i = 1; i < lines.length; i++) {
        expect(
          lines[i].globalStart,
          greaterThanOrEqualTo(lines[i - 1].globalEnd),
          reason: '第 $i 行字符区间倒退（应单调不减），共 $lineCount 逻辑行',
        );
      }
    });
  });
}
