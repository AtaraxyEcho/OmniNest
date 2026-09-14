import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/block_clipper.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_image.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_loader.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_cover_page.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_pagination_engine.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_html_parser.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_content.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 摘要：页面内容所有权唯一化回归（方案 Commit 2，验收矩阵 B 组）。
/// 一个 DOM img 只能由一条解析路径消费；一个 ImageBlock 只能属于一个
/// PageSlice；`段落+图片+段落` 的小章节不得被渲染为封面页。
final _settings = ReaderViewSettings();

Future<ChapterData> _loadChapter(WidgetTester tester, String html) async {
  final loader = ReaderContentLoader(allChapters: const []);
  await tester.runAsync(() async {
    await loader.loadChapter(
      chapterId: 'chapter-1',
      content: ReaderChapterContent(title: '第一章', content: html),
      pageWidth: 320,
      pageHeight: 480,
      settings: _settings,
    );
  });
  final data = loader.getByChapterId('chapter-1');
  expect(data, isNotNull);
  return data!;
}

List<PageSlice> _allSlices(ChapterData data) {
  final navigator = data.getOrCreatePageNavigator(320, 480, _settings);
  final slices = <PageSlice>[];
  for (var i = 0; i < 50; i++) {
    final slice = navigator.getSlice(i);
    if (slice == null) {
      break;
    }
    slices.add(slice);
  }
  return slices;
}

List<ContentBlock> _sliceBlocks(ChapterData data, PageSlice slice) {
  if (slice.endCharOffset > slice.startCharOffset) {
    return BlockClipper.clipBlocksByCharRange(
      data.blocks,
      slice.startCharOffset,
      slice.endCharOffset,
    );
  }
  return BlockClipper.clipBlocksByIndexRange(
    data.blocks,
    slice.startIndex,
    slice.endIndex,
  );
}

int _imageRenderCount(List<List<ContentBlock>> pageBlocks, String src) {
  return pageBlocks
      .expand((blocks) => blocks)
      .whereType<ImageBlock>()
      .where((b) => b.src == src)
      .length;
}

void main() {
  group('B 解析去重（方案 §34）', () {
    test('B4 figure>img>figcaption 只生成一个 ImageBlock', () {
      final blocks = parseBlocks(
        '<figure><img src="same.png"><figcaption>图注</figcaption></figure>',
      );
      final images = blocks.whereType<ImageBlock>().toList();
      expect(images, hasLength(1));
      expect(images.single.caption, '图注');
    });

    test('B5 内联 span>img 只生成一个 ImageBlock', () {
      final blocks = parseBlocks('<p>正文<span><img src="same.png"></span>续</p>');
      // ignore: avoid_print
      print(
        'blocks=${blocks.map((b) => b is ImageBlock ? 'IMG(${b.src})' : b.runtimeType.toString()).join(',')}',
      );
      final images = blocks.whereType<ImageBlock>().toList();
      expect(images, hasLength(1));
    });
  });

  group('B 封面判定拆分（方案 §13-15）', () {
    test('图文混排小章节不得判定为独立封面页', () {
      final blocks = parseBlocks('<p>正文A</p><img src="same.png"><p>正文B</p>');
      expect(
        isCoverLikeChapter(totalChars: 6, blocks: blocks),
        isTrue,
        reason: '旧启发式保留给开书跳过判定',
      );
      expect(
        isDedicatedCoverPage(blocks: blocks),
        isFalse,
        reason: '渲染判定必须走 PageSlice，禁止绕过分页双重渲染图片',
      );
    });

    test('仅图片与仅图片+标题允许独立封面页', () {
      final imagesOnly = parseBlocks('<img src="cover.png">');
      expect(isDedicatedCoverPage(blocks: imagesOnly), isTrue);

      final withTitle = parseBlocks('<h1>书名</h1><img src="cover.png">');
      expect(isDedicatedCoverPage(blocks: withTitle), isTrue);

      final withBody = parseBlocks(
        '<h1>书名</h1><img src="cover.png"><p>前言正文超出标题长度</p>',
      );
      expect(isDedicatedCoverPage(blocks: withBody), isFalse);
    });
  });

  group('B 分页单渲染（方案 §18/验收 B1-B3/B6）', () {
    testWidgets('B1 段落+图片+段落：图片全链路只渲染一次', (tester) async {
      final data = await _loadChapter(
        tester,
        '<p>正文A</p><img src="same.png"><p>正文B</p>',
      );
      final slices = _allSlices(data);
      final pageBlocks = slices.map((s) => _sliceBlocks(data, s)).toList();
      for (var i = 0; i < slices.length; i++) {
        // ignore: avoid_print
        print(
          'slice#$i char=[${slices[i].startCharOffset},${slices[i].endCharOffset}) '
          'block=[${slices[i].startIndex},${slices[i].endIndex}) '
          'blocks=${pageBlocks[i].map((b) => b is ImageBlock ? 'IMG' : b.runtimeType.toString()).join(',')}',
        );
      }
      expect(
        _imageRenderCount(pageBlocks, 'same.png'),
        1,
        reason: 'renderCount == 1 是硬性验收标准',
      );
    });

    testWidgets('B2 图片在前：图片独占页，段落随后', (tester) async {
      final data = await _loadChapter(tester, '<img src="same.png"><p>正文A</p>');
      final slices = _allSlices(data);
      final pageBlocks = slices.map((s) => _sliceBlocks(data, s)).toList();
      expect(pageBlocks, isNotEmpty);
      expect(
        pageBlocks.first.whereType<ImageBlock>().length,
        1,
        reason: '首页应为图片独占页',
      );
      expect(_imageRenderCount(pageBlocks, 'same.png'), 1);
    });

    testWidgets('B3 段落在前：段落页之后图片独占页', (tester) async {
      final data = await _loadChapter(tester, '<p>正文A</p><img src="same.png">');
      final slices = _allSlices(data);
      final pageBlocks = slices.map((s) => _sliceBlocks(data, s)).toList();
      expect(pageBlocks, isNotEmpty);
      expect(
        pageBlocks.first.whereType<ImageBlock>(),
        isEmpty,
        reason: '首页应为段落页',
      );
      expect(
        pageBlocks.last.whereType<ImageBlock>().length,
        1,
        reason: '图片应独占末页',
      );
      expect(_imageRenderCount(pageBlocks, 'same.png'), 1);
    });

    testWidgets('B6 小章节走真实渲染链路：图片渲染数恒为 1', (tester) async {
      // 故意命中旧 isCoverLikeChapter 启发式的小章节。
      final data = await _loadChapter(
        tester,
        '<p>A</p><img src="same.png"><p>B</p>',
      );
      expect(data.totalChars, lessThanOrEqualTo(120));
      final slices = _allSlices(data);
      final pageBlocks = slices.map((s) => _sliceBlocks(data, s)).toList();
      expect(_imageRenderCount(pageBlocks, 'same.png'), 1);

      // 真实渲染链路：逐页构建 ReaderViewContent，统计图片控件数量。
      var renderedImages = 0;
      for (final blocks in pageBlocks) {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ReaderViewContent(
                htmlContent: '',
                settings: _settings,
                visibleBlocks: blocks,
                rawBlocks: data.blocks,
                scrollPhysics: const NeverScrollableScrollPhysics(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        renderedImages +=
            tester
                .widgetList<ReaderContentImage>(find.byType(ReaderContentImage))
                .length;
      }
      expect(renderedImages, 1, reason: 'renderCount == 1 必须在真实渲染组件层成立');
    });
  });

  testWidgets('独立封面章节渲染 Slice 内容而非整章', (tester) async {
    final data = await _loadChapter(tester, '<img src="cover.png"><p>图注文字</p>');
    final slices = _allSlices(data);
    expect(slices, isNotEmpty);
    final firstBlocks = _sliceBlocks(data, slices.first);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ReaderCoverPage(
            title: '书名',
            settings: _settings,
            visibleBlocks: firstBlocks,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final coverImages =
        tester
            .widgetList<ReaderContentImage>(find.byType(ReaderContentImage))
            .length;
    expect(
      coverImages,
      firstBlocks.whereType<ImageBlock>().length,
      reason: '封面页只渲染 Slice 内的图片',
    );
  });
}
