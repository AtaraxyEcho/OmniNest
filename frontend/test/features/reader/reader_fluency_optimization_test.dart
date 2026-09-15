import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/features/reader/application/reader_data_manager.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/block_clipper.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_annotation_handler.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_loader.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_html_parser.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_pagination_engine.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

class MockDataManager extends Mock implements ReaderDataManager {}

ReaderChapterContent _chapterContent({
  String title = '第一章',
  required List<String> paragraphs,
  bool withImage = false,
}) {
  final body = <String>[
    for (var i = 0; i < paragraphs.length; i++) '<p>${paragraphs[i]}</p>',
    if (withImage) '<p><img src="https://example.com/cover.jpg" alt="插图"/></p>',
  ];
  return ReaderChapterContent(title: title, content: body.join());
}

/// 等待分批精测收敛（连续两轮 cumulativeHeights 引用不变）。
Future<void> _waitForHeightConvergence(ChapterData data) async {
  var previous = List<double>.of(data.cumulativeHeights);
  for (var turn = 0; turn < 80; turn++) {
    await Future<void>.delayed(Duration.zero);
    if (identical(previous, data.cumulativeHeights)) {
      return;
    }
    previous = List<double>.of(data.cumulativeHeights);
  }
}

void main() {
  // ─────────────────────────────────────────────────────────
  // S6 字符前缀表：正确性 + 旧线性实现的回归一致性
  // ─────────────────────────────────────────────────────────
  group('blockCharPrefixes', () {
    test('前缀长度、首末值与单调性', () async {
      final loader = ReaderContentLoader(
        allChapters: [ReaderChapter(id: 'c1', title: '一')],
      );
      final settings = ReaderViewSettings();
      final data = await loader.loadChapter(
        chapterId: 'c1',
        content: _chapterContent(
          paragraphs: ['第一段内容。', '第二段内容更长一些，用于区分字符数。', '第三段。'],
          withImage: true,
        ),
        pageWidth: 320,
        pageHeight: 0,
        settings: settings,
        prepareScrollLayout: true,
      );

      final prefixes = data.blockCharPrefixes;
      expect(prefixes.length, data.blocks.length + 1);
      expect(prefixes.first, 0);
      expect(prefixes.last, data.totalChars);
      for (var i = 1; i < prefixes.length; i++) {
        expect(prefixes[i], greaterThanOrEqualTo(prefixes[i - 1]));
      }
      // 图片块零字符：前缀不变
      final imageIdx = data.blocks.indexWhere((b) => b is ImageBlock);
      if (imageIdx >= 0) {
        expect(prefixes[imageIdx + 1], prefixes[imageIdx]);
      }
      // 惰性记忆：重复访问返回同一实例
      expect(identical(prefixes, data.blockCharPrefixes), isTrue);
    });

    test('contentYToCharOffset 无 settings 时精确返回块前缀（回归）', () async {
      final loader = ReaderContentLoader(
        allChapters: [ReaderChapter(id: 'c1', title: '一')],
      );
      final settings = ReaderViewSettings();
      final data = await loader.loadChapter(
        chapterId: 'c1',
        content: _chapterContent(
          paragraphs: ['第一段内容。', '第二段内容更长一些。', '第三段。', '第四段。'],
          withImage: true,
        ),
        pageWidth: 320,
        pageHeight: 0,
        settings: settings,
        prepareScrollLayout: true,
      );
      await _waitForHeightConvergence(data);
      final prefixes = data.blockCharPrefixes;
      final heights = data.cumulativeHeights;

      // 块内中点 Y（settings 为 null 跳过块内精测）精确映射到该块
      // 起始字符前缀——与旧线性累加实现逐点等价。
      for (var i = 0; i < data.blocks.length; i++) {
        final top = i == 0 ? 0.0 : heights[i - 1];
        final bottom = heights[i];
        if (!(bottom > top)) {
          continue; // 零高块无内部点
        }
        final midY = (top + bottom) / 2;
        final expected = prefixes[i];
        final actual = loader.contentYToCharOffset('c1', midY, pageWidth: 320);
        expect(
          actual,
          expected,
          reason: '块 $i 中点的字符偏移应为前缀值 $expected，实际 $actual',
        );
      }
      // 越界钳制
      expect(
        loader.contentYToCharOffset('c1', heights.last + 100, pageWidth: 320),
        prefixes.last,
      );
      expect(loader.contentYToCharOffset('c1', -5, pageWidth: 320), 0);
    });

    test('charOffsetToPixelOffset 块边界精确返回块顶像素（回归）', () async {
      final loader = ReaderContentLoader(
        allChapters: [ReaderChapter(id: 'c1', title: '一')],
      );
      final settings = ReaderViewSettings();
      final data = await loader.loadChapter(
        chapterId: 'c1',
        content: _chapterContent(
          paragraphs: ['第一段内容。', '第二段内容更长一些。', '第三段。'],
          withImage: true,
        ),
        pageWidth: 320,
        pageHeight: 0,
        settings: settings,
        prepareScrollLayout: true,
      );
      await _waitForHeightConvergence(data);
      final prefixes = data.blockCharPrefixes;
      final heights = data.cumulativeHeights;

      for (var i = 0; i < data.blocks.length; i++) {
        if (prefixes[i + 1] == prefixes[i]) {
          continue; // 零字符块没有独占字符偏移，跳过
        }
        final pixel = loader.charOffsetToPixelOffset(
          'c1',
          prefixes[i],
          pageWidth: 320,
          settings: settings,
        );
        final expected = i == 0 ? 0.0 : heights[i - 1];
        expect(
          (pixel - expected).abs(),
          lessThan(0.5),
          reason: '块 $i 起始字符应映射到块顶像素 $expected，实际 $pixel',
        );
      }
      // 越界
      expect(
        loader.charOffsetToPixelOffset(
          'c1',
          0,
          pageWidth: 320,
          settings: settings,
        ),
        0,
      );
      expect(
        loader.charOffsetToPixelOffset(
          'c1',
          data.totalChars,
          pageWidth: 320,
          settings: settings,
        ),
        heights.last,
      );
    });
  });

  // ─────────────────────────────────────────────────────────
  // S7 视觉行测量缓存：身份命中 + 排版参数失效 + 容量淘汰
  // ─────────────────────────────────────────────────────────
  group('measureVisualLines 缓存', () {
    test('同参数重复调用返回同一实例（命中缓存）', () {
      final block = parseBlocks('<p>用于视觉行测量缓存验证的段落文本。</p>').first;
      final settings = ReaderViewSettings();
      final first = ReaderPaginationEngine.measureVisualLines(
        block,
        320,
        settings,
        1.0,
        blockGlobalOffset: 0,
      );
      expect(first, isNotEmpty);
      final second = ReaderPaginationEngine.measureVisualLines(
        block,
        320,
        settings,
        1.0,
        blockGlobalOffset: 0,
      );
      expect(identical(first, second), isTrue);
    });

    test('settings 换实例（排版参数失效）触发重算', () {
      final block = parseBlocks('<p>排版参数变化应触发重算的段落。</p>').first;
      final first = ReaderPaginationEngine.measureVisualLines(
        block,
        320,
        ReaderViewSettings(),
        1.0,
        blockGlobalOffset: 0,
      );
      final second = ReaderPaginationEngine.measureVisualLines(
        block,
        320,
        ReaderViewSettings(),
        1.0,
        blockGlobalOffset: 0,
      );
      expect(identical(first, second), isFalse);
      // 内容等价（同默认排版）
      expect(second.length, first.length);
    });

    test('LRU 容量淘汰后重算仍得到等价结果', () {
      final block = parseBlocks('<p>容量淘汰验证段落，内容保持不变。</p>').first;
      final settings = ReaderViewSettings();
      final first = ReaderPaginationEngine.measureVisualLines(
        block,
        320,
        settings,
        1.0,
        blockGlobalOffset: 0,
      );
      // 填满并溢出缓存（上限 64）
      for (var i = 0; i < 66; i++) {
        ReaderPaginationEngine.measureVisualLines(
          block,
          320 + i.toDouble(),
          settings,
          1.0,
          blockGlobalOffset: 0,
        );
      }
      final again = ReaderPaginationEngine.measureVisualLines(
        block,
        320,
        settings,
        1.0,
        blockGlobalOffset: 0,
      );
      expect(identical(again, first), isFalse, reason: '原条目应已被淘汰');
      expect(again.length, first.length);
      for (var i = 0; i < again.length; i++) {
        expect(again[i].globalStart, first[i].globalStart);
        expect(again[i].height, first[i].height);
      }
    });
  });

  // ─────────────────────────────────────────────────────────
  // S3-1 裁剪结果缓存：身份稳定使下游 identical 判定生效
  // ─────────────────────────────────────────────────────────
  group('clipBlocksByCharRange 缓存', () {
    test('同一 blocks 身份与区间返回同一实例', () {
      final blocks = parseBlocks('<p>第一段。</p><p>第二段。</p><p>第三段。</p>');
      final first = BlockClipper.clipBlocksByCharRange(blocks, 0, 8);
      final second = BlockClipper.clipBlocksByCharRange(blocks, 0, 8);
      expect(identical(first, second), isTrue);
      expect(first, isNotEmpty);
    });

    test('不同区间返回不同实例且内容正确', () {
      final blocks = parseBlocks('<p>第一段。</p><p>第二段。</p><p>第三段。</p>');
      final a = BlockClipper.clipBlocksByCharRange(blocks, 0, 6);
      final b = BlockClipper.clipBlocksByCharRange(blocks, 6, 12);
      expect(identical(a, b), isFalse);
      expect(a, isNotEmpty);
      expect(b, isNotEmpty);
    });

    test('blocks 换新身份（重解析/重排）后重算', () {
      final first = parseBlocks('<p>第一段。</p><p>第二段。</p>');
      final r1 = BlockClipper.clipBlocksByCharRange(first, 0, 6);
      final fresh = parseBlocks('<p>第一段。</p><p>第二段。</p>');
      final r2 = BlockClipper.clipBlocksByCharRange(fresh, 0, 6);
      expect(identical(r1, r2), isFalse, reason: 'blocks 身份变化必须重算');
    });

    test('超出 LRU 容量后淘汰重算，内容等价', () {
      final blocks = parseBlocks('<p>淘汰验证段落。</p>');
      final first = BlockClipper.clipBlocksByCharRange(blocks, 0, 5);
      for (var i = 0; i < 10; i++) {
        BlockClipper.clipBlocksByCharRange(blocks, i, i + 1);
      }
      final again = BlockClipper.clipBlocksByCharRange(blocks, 0, 5);
      expect(identical(again, first), isFalse, reason: '容量 8，首个条目应被淘汰');
      expect(again.length, first.length);
    });
  });

  // ─────────────────────────────────────────────────────────
  // S3-2 章节批注缓存：稳定身份 + 重载/切章失效
  // ─────────────────────────────────────────────────────────
  group('chapterAnnotations 缓存', () {
    late MockDataManager dataManager;

    setUp(() {
      dataManager = MockDataManager();
      registerFallbackValue(
        ReaderAnnotation(
          id: 'x',
          readerItemId: 'item-1',
          chapterId: 'ch-1',
          startOffset: 0,
          endOffset: 1,
          color: '#FFFFFF',
          createdAt: DateTime(2026),
        ),
      );
    });

    ReaderAnnotationHandler createHandler({String chapterId = 'ch-1'}) {
      return ReaderAnnotationHandler(
        itemId: 'item-1',
        chapterId: chapterId,
        dataManager: dataManager,
        settings: ReaderViewSettings(),
        onAnnotationsChanged: () {},
      );
    }

    test('同源同章返回同一实例（整页重建时 downstream identical 生效）', () async {
      final source = <ReaderAnnotation>[];
      when(
        () => dataManager.loadAnnotations(any()),
      ).thenAnswer((_) async => source);
      final handler = createHandler();
      await handler.load();

      final first = handler.chapterAnnotations;
      final second = handler.chapterAnnotations;
      expect(identical(first, second), isTrue);
    });

    test('批注重载（新列表身份）后缓存失效', () async {
      var source = <ReaderAnnotation>[
        ReaderAnnotation(
          id: 'ann-1',
          readerItemId: 'item-1',
          chapterId: 'ch-1',
          startOffset: 0,
          endOffset: 5,
          color: '#FFEB3B',
          createdAt: DateTime(2026),
        ),
      ];
      when(
        () => dataManager.loadAnnotations(any()),
      ).thenAnswer((_) async => source);
      final handler = createHandler();
      await handler.load();
      final before = handler.chapterAnnotations;
      expect(before, hasLength(1));

      // 数据管理器产出新列表（模拟增删批注后的重载）
      source = <ReaderAnnotation>[];
      await handler.load();
      final after = handler.chapterAnnotations;
      expect(identical(before, after), isFalse, reason: '重载必须失效缓存');
      expect(after, isEmpty);
    });

    test('切章后缓存失效', () async {
      final source = <ReaderAnnotation>[
        ReaderAnnotation(
          id: 'ann-1',
          readerItemId: 'item-1',
          chapterId: 'ch-1',
          startOffset: 0,
          endOffset: 5,
          color: '#FFEB3B',
          createdAt: DateTime(2026),
        ),
      ];
      when(
        () => dataManager.loadAnnotations(any()),
      ).thenAnswer((_) async => source);
      final handler = createHandler(chapterId: 'ch-1');
      await handler.load();
      final ch1 = handler.chapterAnnotations;
      expect(ch1, hasLength(1));

      handler.updateChapter('ch-2');
      final ch2 = handler.chapterAnnotations;
      expect(identical(ch1, ch2), isFalse);
      expect(ch2, isEmpty);
    });
  });

  // ─────────────────────────────────────────────────────────
  // S11 预取测高预热：loadChapter 打开 prepareScrollLayout 后
  // 章节立即可用高度表（切章帧零测高）
  // ─────────────────────────────────────────────────────────
  group('prefetch 测高预热', () {
    test('prepareScrollLayout: true 时加载完成即有高度表', () async {
      final loader = ReaderContentLoader(
        allChapters: [ReaderChapter(id: 'c1', title: '一')],
      );
      final data = await loader.loadChapter(
        chapterId: 'c1',
        content: _chapterContent(paragraphs: ['第一段。', '第二段。']),
        pageWidth: 320,
        pageHeight: 0,
        settings: ReaderViewSettings(),
        prepareScrollLayout: true,
      );
      expect(data.cumulativeHeights, isNotEmpty);
      expect(data.cumulativeHeights.length, data.blocks.length);
    });

    test('prepareScrollLayout: false 维持懒测量（高度表为空）', () async {
      final loader = ReaderContentLoader(
        allChapters: [ReaderChapter(id: 'c1', title: '一')],
      );
      final data = await loader.loadChapter(
        chapterId: 'c1',
        content: _chapterContent(paragraphs: ['第一段。', '第二段。']),
        pageWidth: 320,
        pageHeight: 0,
        settings: ReaderViewSettings(),
        prepareScrollLayout: false,
      );
      expect(data.cumulativeHeights, isEmpty);
    });
  });
}
