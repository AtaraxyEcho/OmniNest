import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_loader.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'layout invalidation does not re-enter ensureScrollLayout synchronously',
    () async {
      final loader = ReaderContentLoader(
        allChapters: [
          ReaderChapter(id: 'c0', title: 'A'),
          ReaderChapter(id: 'c1', title: 'B'),
        ],
      );
      final settings = ReaderViewSettings();
      var inCallback = false;
      var reentered = false;
      var calls = 0;

      loader.onLayoutInvalidated = () {
        calls++;
        if (inCallback) {
          reentered = true;
          return;
        }
        inCallback = true;
        // 模拟 UI 在回调里立刻 rebuild：若 notify 为同步会栈溢出。
        loader.ensureScrollLayoutForNeighbors(
          'c0',
          pageWidth: 320,
          settings: settings,
        );
        inCallback = false;
      };

      await loader.loadChapter(
        chapterId: 'c0',
        content: ReaderChapterContent(
          title: 'A',
          content: '<p>${'字' * 200}</p>',
        ),
        pageWidth: 320,
        pageHeight: 0,
        settings: settings,
        prepareScrollLayout: true,
      );
      loader.setActive('c0');
      loader.ensureScrollLayoutForNeighbors(
        'c0',
        pageWidth: 320,
        settings: settings,
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(reentered, isFalse, reason: 'notify must not be synchronous');
      expect(calls, greaterThanOrEqualTo(1));
      expect(loader.getByChapterId('c0')!.hasPreciseHeights, isTrue);
    },
  );
}
