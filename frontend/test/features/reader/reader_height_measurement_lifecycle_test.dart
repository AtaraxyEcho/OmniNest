import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_loader.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_pagination_engine.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 测高生命周期回归测试（D-18 / D-19 / D-20 / D-23c）。
///
/// 共同不变式：任何一章一旦开始精测，就必须能收敛到 `hasPreciseHeights`，
/// 不受邻章预取、恢复轮询或设置重算的干扰；不收敛会让进度与恢复落点
/// 永久按估算高度计算，或在恢复等待中撞超时。
void main() {
  ReaderChapterContent chapterContent(String title, int paragraphs) {
    return ReaderChapterContent(
      title: title,
      // 段落与分隔线交错：合并会把连续段落压成单块，那样测高没有分批可言。
      content:
          List.generate(
            paragraphs,
            (index) => '<p>第 $index 段正文，用于测高生命周期验证。</p><hr/>',
          ).join(),
    );
  }

  Future<void> settle(ChapterData data, {int maxTurns = 200}) async {
    for (var turn = 0; turn < maxTurns; turn++) {
      if (data.hasPreciseHeights) {
        return;
      }
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('邻章预取不得中断当前章的精测', () async {
    final loader = ReaderContentLoader(
      allChapters: const [
        ReaderChapter(id: 'chapter-1', title: '第一章'),
        ReaderChapter(id: 'chapter-2', title: '第二章'),
      ],
    );
    final settings = ReaderViewSettings();
    loader.setActive('chapter-1');

    final current = await loader.loadChapter(
      chapterId: 'chapter-1',
      // 块数必须超出同步预算（每段 p+hr 两块）：小章首帧就测完整章，
      // 精测不再在途，本用例要验的"在途精测不被邻章打断"就无从发生。
      content: chapterContent('第一章', 120),
      pageWidth: 320,
      pageHeight: 0,
      settings: settings,
    );
    // 当前章精测在途时预取邻章
    await loader.loadChapter(
      chapterId: 'chapter-2',
      content: chapterContent('第二章', 60),
      pageWidth: 320,
      pageHeight: 0,
      settings: settings,
      prepareScrollLayout: true,
    );

    await settle(current);
    expect(current.hasPreciseHeights, isTrue, reason: '预取推进测高代次会把当前章永久留在估算高度');
  });

  test('恢复轮询共享同一个在途精测并能收敛', () async {
    final loader = ReaderContentLoader(
      allChapters: const [ReaderChapter(id: 'chapter-1', title: '第一章')],
    );
    final settings = ReaderViewSettings();
    loader.setActive('chapter-1');
    final data = await loader.loadChapter(
      chapterId: 'chapter-1',
      // 超出同步预算才有"在途精测"可共享；小章首帧已测完，轮询无需收敛。
      content: chapterContent('第一章', 120),
      pageWidth: 320,
      pageHeight: 0,
      settings: settings,
    );
    expect(data.hasPreciseHeights, isFalse, reason: '刚加载完应仍是估算高度');

    // 模拟恢复落位每帧轮询：旧实现每次调用都从第 0 块重排一轮并杀死上一轮。
    for (var poll = 0; poll < 40; poll++) {
      unawaited(
        loader.ensurePreciseHeights(
          chapterId: 'chapter-1',
          pageWidth: 320,
          settings: settings,
          textScale: 1.0,
        ),
      );
      await Future<void>.delayed(Duration.zero);
    }

    await settle(data);
    expect(data.hasPreciseHeights, isTrue, reason: '互相杀死的精测轮次会让恢复永远等不到精测收敛');
  });

  test('改字号同步重测后直接视为已精测', () async {
    final loader = ReaderContentLoader(
      allChapters: const [ReaderChapter(id: 'chapter-1', title: '第一章')],
    );
    final settings = ReaderViewSettings();
    loader.setActive('chapter-1');
    final data = await loader.loadChapter(
      chapterId: 'chapter-1',
      content: chapterContent('第一章', 40),
      pageWidth: 320,
      pageHeight: 0,
      settings: settings,
    );
    await settle(data);

    loader.rekeyAndRecomputeHeights(
      'chapter-1',
      320,
      settings.copyWith(fontSize: settings.fontSize + 2),
      1.0,
    );

    expect(
      data.hasPreciseHeights,
      isTrue,
      reason: '同步重测本身就是逐块实测，标记缺失会让下一次恢复再整章重测',
    );
  });

  test('预取章节只做头部估算，不做全量精测', () async {
    final loader = ReaderContentLoader(
      allChapters: const [
        ReaderChapter(id: 'chapter-1', title: '第一章'),
        ReaderChapter(id: 'chapter-2', title: '第二章'),
      ],
    );
    final settings = ReaderViewSettings();
    loader.setActive('chapter-1');
    await loader.loadChapter(
      chapterId: 'chapter-1',
      content: chapterContent('第一章', 10),
      pageWidth: 320,
      pageHeight: 0,
      settings: settings,
    );

    final prefetched = await loader.loadChapter(
      chapterId: 'chapter-2',
      content: chapterContent('第二章', 60),
      pageWidth: 320,
      pageHeight: 0,
      settings: settings,
      prepareScrollLayout: true,
    );
    await Future<void>.delayed(Duration.zero);

    expect(prefetched.cumulativeHeights, isNotEmpty, reason: '滚动映射需要即时高度表');
    expect(
      prefetched.hasPreciseHeights,
      isFalse,
      reason: '未成为当前章前不应为它跑完整 TextPainter 精测',
    );
  });

  test('列宽作废后必须按新宽收敛，不得复用旧参数的在途任务', () async {
    final loader = ReaderContentLoader(
      allChapters: const [ReaderChapter(id: 'chapter-1', title: '第一章')],
    );
    final settings = ReaderViewSettings();
    loader.setActive('chapter-1');
    final data = await loader.loadChapter(
      chapterId: 'chapter-1',
      content: chapterContent('第一章', 120),
      pageWidth: 320,
      pageHeight: 0,
      settings: settings,
    );

    // 让 320 宽这一轮跑过至少一个批次边界，才谈得上"在途被作废"
    for (var turn = 0; turn < 3; turn++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(data.measuredThrough, greaterThan(0), reason: '前置条件：旧宽精测已发布过批次');

    await loader.loadChapter(
      chapterId: 'chapter-1',
      content: chapterContent('第一章', 120),
      pageWidth: 140,
      pageHeight: 0,
      settings: settings,
    );
    await settle(data, maxTurns: 400);

    expect(
      data.hasPreciseHeights,
      isTrue,
      reason: '抬代次只杀掉旧任务却没释放在途句柄，新一轮会复用旧任务并直接早退，整章永久停在估算上',
    );
    final reference = <double>[];
    var cumulative = 0.0;
    for (final block in data.blocks) {
      cumulative += ReaderPaginationEngine.measureBlockHeight(
        block,
        140,
        settings,
      );
      reference.add(cumulative);
    }
    for (var i = 0; i < reference.length; i++) {
      expect(
        (data.cumulativeHeights[i] - reference[i]).abs(),
        lessThan(0.51),
        reason: '第 $i 块仍是旧列宽的值：作废后的旧任务在批次边界先发布后校验',
      );
    }
  });

  test('预取过的章节成为当前章后必须补排精测', () async {
    final loader = ReaderContentLoader(
      allChapters: const [
        ReaderChapter(id: 'chapter-1', title: '第一章'),
        ReaderChapter(id: 'chapter-2', title: '第二章'),
      ],
    );
    final settings = ReaderViewSettings();
    loader.setActive('chapter-1');

    final prefetched = await loader.loadChapter(
      chapterId: 'chapter-2',
      content: chapterContent('第二章', 120),
      pageWidth: 320,
      pageHeight: 0,
      settings: settings,
      prepareScrollLayout: true,
    );
    await Future<void>.delayed(Duration.zero);
    expect(prefetched.hasPreciseHeights, isFalse, reason: '前置条件：预取时只填估算表');

    loader.setActive('chapter-2');
    await loader.loadChapter(
      chapterId: 'chapter-2',
      content: chapterContent('第二章', 120),
      pageWidth: 320,
      pageHeight: 0,
      settings: settings,
    );
    await settle(prefetched, maxTurns: 400);

    expect(
      prefetched.hasPreciseHeights,
      isTrue,
      reason: '表已属于当前排版但只是估算：布局不“过期”，于是再没人补精测，顺序通读全程按均值算进度与落点',
    );
  });
}
