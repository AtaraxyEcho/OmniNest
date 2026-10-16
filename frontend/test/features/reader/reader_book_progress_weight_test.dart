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
    bool chapterLoaded = true,
  }) {
    return computeBookProgress(
      manifestCharCounts: _manifest,
      currentChapterIndex: chapterIndex,
      paintedChapterChars: paintedChars,
      chapterOffsetChars: offsetChars,
      chapterLoaded: chapterLoaded,
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

    test('本章尚未加载出字符时判为未知，不拿章内比例冒充', () {
      expect(
        progress(
          chapterIndex: 1,
          paintedChars: 0,
          offsetChars: 0,
          chapterLoaded: false,
        ),
        isNull,
      );
    });

    test('纯图章按章首基准计读数，不沿用上一章的全书比例', () {
      // 封面章与全屏插图章没有绘出字符：读到哪就是章首。判成"未知"会让
      // resolveBookProgress 回退到上一章的 lastKnown，跳章后立即退出就把新章
      // 配上旧章的百分比上报给服务端。
      expect(
        progress(chapterIndex: 1, paintedChars: 0, offsetChars: 0),
        closeTo(1 / 3, 1e-9),
      );
      expect(
        progress(chapterIndex: 2, paintedChars: 0, offsetChars: 0),
        closeTo(2 / 3, 1e-9),
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
        progress(
          chapterIndex: 2,
          paintedChars: 0,
          offsetChars: 0,
          chapterLoaded: false,
        ),
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
      bool chapterLoaded = true,
    }) {
      return resolveBookProgress(
        manifestCharCounts: manifest,
        currentChapterIndex: chapterIndex,
        paintedChapterChars: paintedChars,
        chapterOffsetChars: offsetChars,
        lastKnown: lastKnown,
        chapterLoaded: chapterLoaded,
      );
    }

    test('可算出时以本次读数为准', () {
      expect(resolve(lastKnown: 0.9), closeTo(0.5, 1e-9));
    });

    test('本章未加载出字符数时沿用最近一次已知值', () {
      expect(
        resolve(paintedChars: 0, lastKnown: 0.4, chapterLoaded: false),
        0.4,
      );
    });

    test('清单尚未就绪时沿用最近一次已知值', () {
      expect(resolve(manifest: null, lastKnown: 0.4), 0.4);
      expect(resolve(manifest: const [], lastKnown: 0.4), 0.4);
    });

    test('从未算出过时保持未知，不回落到章内比例', () {
      expect(
        resolve(paintedChars: 0, lastKnown: null, chapterLoaded: false),
        isNull,
      );
      expect(resolve(manifest: const [], lastKnown: null), isNull);
    });

    test('当前章不在清单中时沿用最近一次已知值', () {
      expect(resolve(chapterIndex: -1, lastKnown: 0.25), 0.25);
    });
  });

  // 底栏进度条拖拽要把全书比例换回"第几章的百分之几"：比例的分母是清单字符数，
  // 落位偏移是客户端块字符域，直接当偏移传过去会让长章节落到别处。
  group('seekTargetFromBookProgress', () {
    test('往返一致：拖到某处再读数应回到同一个比例', () {
      for (final ratio in [0.0, 0.17, 0.5, 0.83, 1.0]) {
        final target = seekTargetFromBookProgress(
          manifestCharCounts: _manifest,
          progress: ratio,
        );
        final back = computeBookProgress(
          manifestCharCounts: _manifest,
          currentChapterIndex: target.chapterIndex,
          paintedChapterChars: 100,
          chapterOffsetChars: (target.chapterRatio * 100).round(),
        );
        expect(back, closeTo(ratio, 0.01));
      }
    });

    test('等长清单按比例切章', () {
      final first = seekTargetFromBookProgress(
        manifestCharCounts: _manifest,
        progress: 0.2,
      );
      expect(first.chapterIndex, 0);
      expect(first.chapterRatio, closeTo(0.6, 1e-9));

      final second = seekTargetFromBookProgress(
        manifestCharCounts: _manifest,
        progress: 1 / 3,
      );
      expect(second.chapterIndex, 1);
      expect(second.chapterRatio, closeTo(0.0, 1e-9));

      final last = seekTargetFromBookProgress(
        manifestCharCounts: _manifest,
        progress: 0.9,
      );
      expect(last.chapterIndex, 2);
      expect(last.chapterRatio, closeTo(0.7, 1e-9));
    });

    test('章长悬殊时按清单权重选章，而不是按章序号均分', () {
      const counts = [10, 990];
      // 全书 0.5% 是短章的一半：按章序号均分会把它派到第一章章首。
      final target = seekTargetFromBookProgress(
        manifestCharCounts: counts,
        progress: 0.005,
      );
      expect(target.chapterIndex, 0);
      expect(target.chapterRatio, closeTo(0.5, 1e-9));

      final late = seekTargetFromBookProgress(
        manifestCharCounts: counts,
        progress: 0.5,
      );
      expect(late.chapterIndex, 1);
      expect(late.chapterRatio, closeTo((0.5 * 1000 - 10) / 990, 1e-9));
    });

    test('末尾比例落在最后一章章末，不越界', () {
      final target = seekTargetFromBookProgress(
        manifestCharCounts: _manifest,
        progress: 1.0,
      );
      expect(target.chapterIndex, _manifest.length - 1);
      expect(target.chapterRatio, closeTo(1.0, 1e-9));
    });

    test('超界比例先夹紧，清单为空时退回章首', () {
      final clamped = seekTargetFromBookProgress(
        manifestCharCounts: _manifest,
        progress: 1.8,
      );
      expect(clamped.chapterIndex, 2);
      expect(clamped.chapterRatio, closeTo(1.0, 1e-9));

      expect(
        seekTargetFromBookProgress(manifestCharCounts: const [], progress: 0.5),
        (chapterIndex: 0, chapterRatio: 0.0),
      );
    });
  });
}
