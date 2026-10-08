import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_loader.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 摘要：高度表必须随列宽与文字缩放失效。
///
/// 高度表缓存键只含章节与字号/行高/字体，视口宽度变化后旧表被当作有效值继续
/// 使用：条目实际高度与表不符，字符偏移↔像素映射整章偏；而自 #97f93772 起
/// 这份表还直接决定滚动范围。
void main() {
  final settings = ReaderViewSettings(
    fontFamily: 'sans',
    fontSize: 18,
    lineHeight: 1.6,
  );
  final content = ReaderChapterContent(
    title: '第一章',
    content: '<p>${List<String>.filled(240, 'word').join(' ')}</p>',
  );
  final chapters = [
    ReaderChapter(id: 'chapter_1', chapterNumber: 1, title: '第一章'),
  ];

  Future<double> totalHeightOnce({
    required double pageWidth,
    double textScale = 1.0,
  }) async {
    final loader = ReaderContentLoader(allChapters: chapters);
    final data = await loader.loadChapter(
      chapterId: 'chapter_1',
      content: content,
      pageWidth: pageWidth,
      pageHeight: 600,
      settings: settings,
      textScale: textScale,
    );
    return data.cumulativeHeights.isEmpty ? 0.0 : data.cumulativeHeights.last;
  }

  /// 先按 firstWidth 测得，再按 secondWidth 重新加载同一章。
  Future<double> totalHeightAfterReload({
    required double firstWidth,
    required double secondWidth,
    double secondTextScale = 1.0,
  }) async {
    final loader = ReaderContentLoader(allChapters: chapters);
    await loader.loadChapter(
      chapterId: 'chapter_1',
      content: content,
      pageWidth: firstWidth,
      pageHeight: 600,
      settings: settings,
    );
    final data = await loader.loadChapter(
      chapterId: 'chapter_1',
      content: content,
      pageWidth: secondWidth,
      pageHeight: 600,
      settings: settings,
      textScale: secondTextScale,
    );
    return data.cumulativeHeights.isEmpty ? 0.0 : data.cumulativeHeights.last;
  }

  group('高度表失效', () {
    test('前提：更窄的列显著更高', () async {
      final wide = await totalHeightOnce(pageWidth: 700);
      final narrow = await totalHeightOnce(pageWidth: 300);
      expect(wide, greaterThan(0));
      expect(narrow, greaterThan(wide * 1.5));
    });

    test('列宽变化后重新加载必须按新宽度重算', () async {
      final narrow = await totalHeightOnce(pageWidth: 300);
      final resized = await totalHeightAfterReload(
        firstWidth: 700,
        secondWidth: 300,
      );
      expect(
        resized,
        closeTo(narrow, 1.0),
        reason: '先按 700 宽测得再按 300 宽重载，仍得到旧表：$resized 对 $narrow',
      );
    });

    test('文字缩放变化后必须按新缩放重算', () async {
      final scaled = await totalHeightOnce(pageWidth: 500, textScale: 1.4);
      final resized = await totalHeightAfterReload(
        firstWidth: 500,
        secondWidth: 500,
        secondTextScale: 1.4,
      );
      expect(
        resized,
        closeTo(scaled, 1.0),
        reason: '1.0 缩放的旧表被 1.4 复用：$resized 对 $scaled',
      );
    });

    test('同参数重复加载保持同一结果', () async {
      final stable = await totalHeightAfterReload(
        firstWidth: 600,
        secondWidth: 600,
      );
      final single = await totalHeightOnce(pageWidth: 600);
      expect(stable, closeTo(single, 1.0));
    });
  });
}
