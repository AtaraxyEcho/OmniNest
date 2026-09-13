import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/application/reader_chapter_load_coordinator.dart';

void main() {
  group('ReaderChapterLoadCoordinator', () {
    test('ignores stale results after chapter switch', () {
      final coordinator = ReaderChapterLoadCoordinator();
      final first = coordinator.begin('chapter-1');
      final second = coordinator.begin('chapter-2');

      coordinator.succeed(first, 'chapter-1');

      expect(coordinator.isLoading, isTrue);
      expect(coordinator.loadingChapterId, 'chapter-2');
      expect(coordinator.isCurrent(second, 'chapter-2'), isTrue);
    });

    test('keeps failure until an explicit retry', () {
      final coordinator = ReaderChapterLoadCoordinator();
      final generation = coordinator.begin('chapter-1');

      coordinator.fail(generation, 'chapter-1');

      expect(coordinator.isLoading, isFalse);
      expect(coordinator.hasFailed('chapter-1'), isTrue);

      coordinator.clearFailure('chapter-1');

      expect(coordinator.hasFailed('chapter-1'), isFalse);
    });

    test(
      'releaseIfCurrent clears stale occupancy so isLoading cannot stick',
      () {
        final coordinator = ReaderChapterLoadCoordinator();
        final generation = coordinator.begin('chapter-1');
        expect(coordinator.isLoading, isTrue);

        // 章节被切走/收养改写，结果不再被消费：释放占用。
        coordinator.releaseIfCurrent(generation, 'chapter-1');

        expect(coordinator.isLoading, isFalse);
        // 释放后旧代次结果视为过期，不得覆盖状态。
        coordinator.succeed(generation, 'chapter-1');
        expect(coordinator.isLoading, isFalse);
      },
    );

    test('releaseIfCurrent ignores superseded requests', () {
      final coordinator = ReaderChapterLoadCoordinator();
      final first = coordinator.begin('chapter-1');
      final second = coordinator.begin('chapter-2');

      coordinator.releaseIfCurrent(first, 'chapter-1');

      // 旧请求不匹配当前代次：不得误清后续请求的占用。
      expect(coordinator.isLoading, isTrue);
      expect(coordinator.loadingChapterId, 'chapter-2');

      coordinator.releaseIfCurrent(second, 'chapter-1');
      expect(coordinator.isLoading, isTrue);
      expect(coordinator.loadingChapterId, 'chapter-2');
    });
  });
}
