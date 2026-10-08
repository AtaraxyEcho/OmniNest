import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/pages/reader_view_page.dart';

/// 摘要：钉住全书进度的权重口径——分母恒为清单字符数，当前章只贡献「章内比例 × 清单权重」。
///
/// 服务端 EPUB 清单的 charCount 由 DOM 文本节点直接统计（不折叠空白），与客户端折叠空白后的
/// painted 值本就不同口径。旧写法把当前章的 painted 值写回权重数组，等于每翻开一章就改掉分母，
/// 读数会随「翻开某章」而不是「读到某处」变化，并在章节交界处前后不一致。
void main() {
  // 三章清单各 1000 字；实际渲染出来 950 / 900 / 1000。
  const manifest = [1000, 1000, 1000];

  double progress({
    required int chapterIndex,
    required int paintedChars,
    required int offsetChars,
    double fallback = 0.0,
  }) {
    return computeBookProgress(
      manifestCharCounts: manifest,
      currentChapterIndex: chapterIndex,
      paintedChapterChars: paintedChars,
      chapterOffsetChars: offsetChars,
      fallbackChapterRatio: fallback,
    );
  }

  group('computeBookProgress', () {
    test('章末与下一章章首给出同一个读数', () {
      final endOfFirst = progress(
        chapterIndex: 0,
        paintedChars: 950,
        offsetChars: 950,
      );
      final startOfSecond = progress(
        chapterIndex: 1,
        paintedChars: 900,
        offsetChars: 0,
      );

      expect(endOfFirst, closeTo(1 / 3, 1e-9));
      expect(startOfSecond, closeTo(endOfFirst, 1e-9));
    });

    test('翻开一章不改变读数', () {
      final thinChapter = progress(
        chapterIndex: 1,
        paintedChars: 900,
        offsetChars: 0,
      );
      final wideChapter = progress(
        chapterIndex: 1,
        paintedChars: 1600,
        offsetChars: 0,
      );

      expect(thinChapter, closeTo(1 / 3, 1e-9));
      expect(wideChapter, closeTo(thinChapter, 1e-9));
    });

    test('章内按推进比例计入，与 painted 绝对值无关', () {
      expect(
        progress(chapterIndex: 1, paintedChars: 900, offsetChars: 450),
        closeTo(0.5, 1e-9),
      );
      expect(
        progress(chapterIndex: 1, paintedChars: 1800, offsetChars: 900),
        closeTo(0.5, 1e-9),
      );
    });

    test('偏移超出本章字符数时限定在章末', () {
      expect(
        progress(chapterIndex: 1, paintedChars: 900, offsetChars: 1200),
        closeTo(2 / 3, 1e-9),
      );
    });

    test('全书读完为 1.0', () {
      expect(
        progress(chapterIndex: 2, paintedChars: 1000, offsetChars: 1000),
        1.0,
      );
    });

    test('本章尚未解析出字符时回退到章内滚动比例', () {
      expect(
        progress(
          chapterIndex: 1,
          paintedChars: 0,
          offsetChars: 0,
          fallback: 0.4,
        ),
        closeTo((1000 + 1000 * 0.4) / 3000, 1e-9),
      );
    });

    test('当前章不在清单中时按首章计，不抛异常', () {
      expect(
        progress(chapterIndex: -1, paintedChars: 950, offsetChars: 475),
        closeTo(0.5 / 3, 1e-9),
      );
    });

    test('清单为空或总字符为 0 时回退到章内滚动比例', () {
      expect(
        computeBookProgress(
          manifestCharCounts: const [],
          currentChapterIndex: 0,
          paintedChapterChars: 900,
          chapterOffsetChars: 300,
          fallbackChapterRatio: 0.25,
        ),
        0.25,
      );
      expect(
        computeBookProgress(
          manifestCharCounts: const [0, 0],
          currentChapterIndex: 1,
          paintedChapterChars: 900,
          chapterOffsetChars: 300,
          fallbackChapterRatio: 0.25,
        ),
        0.25,
      );
    });
  });
}
