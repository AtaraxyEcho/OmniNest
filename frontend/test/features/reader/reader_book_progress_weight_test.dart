import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/pages/reader_view_page.dart';

/// 摘要：钉住全书进度的权重口径——分母恒为清单字符数，当前章只贡献「章内比例 × 清单权重」，
/// 口径无法确定时返回 null 而不是回退成章内比例。
///
/// 服务端 EPUB 清单的 charCount 由 DOM 文本节点直接统计（不折叠空白），与客户端折叠空白后的
/// painted 值本就不同口径。旧写法把当前章的 painted 值写回权重数组，等于每翻开一章就改掉分母，
/// 读数会随「翻开某章」而不是「读到某处」变化，并在章节交界处前后不一致。
/// 回退成章内比例是更糟的口径混合：任意长章章尾都会被记成接近读完。
/// 三章清单各 1000 字；实际渲染出来 950 / 900 / 1000。
const _manifest = [1000, 1000, 1000];

void main() {
  double? progress({
    required int chapterIndex,
    required int paintedChars,
    required int offsetChars,
  }) {
    return computeBookProgress(
      manifestCharCounts: _manifest,
      currentChapterIndex: chapterIndex,
      paintedChapterChars: paintedChars,
      chapterOffsetChars: offsetChars,
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
      expect(startOfSecond, closeTo(endOfFirst!, 1e-9));
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
      expect(wideChapter, closeTo(thinChapter!, 1e-9));
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

    test('本章尚未解析出字符时判为未知，不拿章内比例冒充', () {
      expect(
        progress(chapterIndex: 1, paintedChars: 0, offsetChars: 0),
        isNull,
      );
    });

    test('当前章不在清单中时判为未知，不按首章硬算', () {
      expect(
        progress(chapterIndex: -1, paintedChars: 950, offsetChars: 475),
        isNull,
      );
    });

    test('清单为空或总字符为 0 时判为未知', () {
      expect(
        computeBookProgress(
          manifestCharCounts: const [],
          currentChapterIndex: 0,
          paintedChapterChars: 900,
          chapterOffsetChars: 300,
        ),
        isNull,
      );
      expect(
        computeBookProgress(
          manifestCharCounts: const [0, 0],
          currentChapterIndex: 1,
          paintedChapterChars: 900,
          chapterOffsetChars: 300,
        ),
        isNull,
      );
    });

    test('未知读数不得比错误读数更安全地被上报', () {
      // 全书口径未知时调用方必须跳过进度上报；章内比例作为全书比例上传
      // 会让任意章章尾被记成接近读完，续读列表百分比虚高。
      expect(
        progress(chapterIndex: 2, paintedChars: 0, offsetChars: 0),
        isNull,
      );
    });
  });

  group('resolveBookProgress', () {
    // 显示与上报共用这条入口：口径暂时不可用时要沿用最近一次已知值，
    // 常驻进度胶囊不必在切章或测高期间掉回 0%；从未算出过才保持未知。
    double? resolve({
      List<int>? manifest = _manifest,
      int chapterIndex = 1,
      int paintedChars = 900,
      int offsetChars = 450,
      double? lastKnown,
    }) {
      return resolveBookProgress(
        manifestCharCounts: manifest,
        currentChapterIndex: chapterIndex,
        paintedChapterChars: paintedChars,
        chapterOffsetChars: offsetChars,
        lastKnown: lastKnown,
      );
    }

    test('可算出时以本次读数为准', () {
      expect(resolve(lastKnown: 0.9), closeTo(0.5, 1e-9));
    });

    test('本章未测出字符数时沿用最近一次已知值', () {
      expect(resolve(paintedChars: 0, lastKnown: 0.4), 0.4);
    });

    test('清单尚未就绪时沿用最近一次已知值', () {
      expect(resolve(manifest: null, lastKnown: 0.4), 0.4);
      expect(resolve(manifest: const [], lastKnown: 0.4), 0.4);
    });

    test('从未算出过时保持未知，不回落到章内比例', () {
      expect(resolve(paintedChars: 0, lastKnown: null), isNull);
      expect(resolve(manifest: const [], lastKnown: null), isNull);
    });

    test('当前章不在清单中时沿用最近一次已知值', () {
      expect(resolve(chapterIndex: -1, lastKnown: 0.25), 0.25);
    });
  });
}
