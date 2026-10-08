import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_loader.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';

/// 摘要：滚动模式下高度表过期时必须被发现。
///
/// 页模式有 LayoutBuilder 触发重排，滚动模式没有：视口变化后表会一直按旧列宽
/// 使用，而该表既驱动字符↔像素映射，也直接决定滚动范围。
void main() {
  group('scrollMetricsStale', () {
    test('列宽一致且缩放一致时不重算', () {
      expect(
        scrollMetricsStale(
          tablePageWidth: 560,
          tableTextScale: 1,
          pageWidth: 560,
          textScale: 1,
        ),
        isFalse,
      );
    });

    test('列宽变化即过期', () {
      expect(
        scrollMetricsStale(
          tablePageWidth: 560,
          tableTextScale: 1,
          pageWidth: 700,
          textScale: 1,
        ),
        isTrue,
      );
    });

    test('文字缩放变化即过期', () {
      expect(
        scrollMetricsStale(
          tablePageWidth: 560,
          tableTextScale: 1,
          pageWidth: 560,
          textScale: 1.25,
        ),
        isTrue,
      );
    });

    test('从未记录过布局参数也视为过期（表不属于当前宽度）', () {
      expect(
        scrollMetricsStale(
          tablePageWidth: -1,
          tableTextScale: -1,
          pageWidth: 560,
          textScale: 1,
        ),
        isTrue,
      );
    });
  });

  group('ChapterData 布局印章', () {
    test('标记账号后与表参数一致', () {
      final data = ChapterData(
        chapterId: 'chapter_1',
        content: ReaderChapterContent(title: '第一章', content: '<p>x</p>'),
        blocks: const [],
      );
      expect(data.scrollLayoutPageWidth, -1);
      data.markScrollLayout(560, 1.25);
      expect(data.scrollLayoutPageWidth, 560);
      expect(data.scrollLayoutTextScale, 1.25);
    });
  });
}
