import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_position_tracker.dart';

/// 摘要：回归翻页模式进度口径（占位总页数导致 chapterProgress 恒为 0）。
///
/// 懒分页不预知总页数，旧签名却要求调用方传 totalPages，唯一调用点传了
/// 占位值 10000，于是页模式保存的 chapterProgress 恒为 pageIndex/9999≈0，
/// 与滚动模式的字符偏移口径分裂；同一本书两种模式的进度不可比。
void main() {
  group('ReaderPositionTracker.updateFromPage', () {
    test('按字符偏移推导章节进度，不需要总页数', () {
      final tracker = ReaderPositionTracker();
      tracker.updateFromPage(
        charOffset: 500,
        chapterId: 'c1',
        totalChars: 2000,
      );

      expect(tracker.charOffset, 500);
      expect(tracker.chapterProgress, closeTo(0.25, 1e-9));
    });

    test('与滚动模式同口径：相同 charOffset 得到相同章节进度', () {
      final pageTracker = ReaderPositionTracker();
      final scrollTracker = ReaderPositionTracker();
      pageTracker.updateFromPage(
        charOffset: 1200,
        chapterId: 'c1',
        totalChars: 3000,
      );
      scrollTracker.updateFromScroll(
        offset: 0,
        maxExtent: 1000,
        totalChars: 3000,
        chapterId: 'c1',
        charOffset: 1200,
      );

      expect(
        pageTracker.chapterProgress,
        closeTo(scrollTracker.chapterProgress, 1e-9),
      );
    });

    test('超出章节字符数时夹紧到 1.0', () {
      final tracker = ReaderPositionTracker();
      tracker.updateFromPage(
        charOffset: 4000,
        chapterId: 'c1',
        totalChars: 2000,
      );

      expect(tracker.chapterProgress, 1.0);
    });

    test('空章节退到全书位置，单章书保持 0', () {
      final multiChapter = ReaderPositionTracker();
      multiChapter.updateFromPage(
        charOffset: 0,
        chapterId: 'c3',
        totalChars: 0,
        totalChapters: 5,
        currentChapterIndex: 2,
      );
      expect(multiChapter.chapterProgress, closeTo(0.5, 1e-9));

      final singleChapter = ReaderPositionTracker();
      singleChapter.updateFromPage(
        charOffset: 0,
        chapterId: 'c1',
        totalChars: 0,
        totalChapters: 1,
        currentChapterIndex: 0,
      );
      expect(singleChapter.chapterProgress, 0.0);
    });

    test('记录当前章身份', () {
      final tracker = ReaderPositionTracker();
      expect(tracker.chapterId, '');

      tracker.updateFromPage(charOffset: 10, chapterId: 'c9', totalChars: 100);
      expect(tracker.chapterId, 'c9');
    });
  });
}
