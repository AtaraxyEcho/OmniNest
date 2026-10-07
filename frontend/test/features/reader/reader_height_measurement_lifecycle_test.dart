import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_loader.dart';
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
      content: chapterContent('第一章', 60),
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
      content: chapterContent('第一章', 60),
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
}
