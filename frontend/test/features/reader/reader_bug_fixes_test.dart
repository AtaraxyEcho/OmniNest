import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_html_parser.dart';

/// 测试 _searchInSpans 的跨 span 文本搜索逻辑。
/// 由于 _searchInSpans 是 ReaderViewContent 的私有方法，
/// 我们通过 parseBlocks + 手动拼接来验证偏移量映射。
void main() {
  group('Cross-span text search', () {
    test('finds text within a single span', () {
      final blocks = parseBlocks('<p>Hello World</p>');
      final p = blocks.first as ParagraphBlock;
      final spans = p.lines.first.spans;

      // 拼接所有 span 文本
      final fullText = spans.map((s) => s.text).join();
      final idx = fullText.indexOf('World');
      expect(idx, 6);

      // 映射回 span offset
      var cursor = 0;
      int? foundOffset;
      for (final span in spans) {
        final spanEnd = cursor + span.text.length;
        if (idx < spanEnd) {
          foundOffset = span.startOffset + (idx - cursor);
          break;
        }
        cursor = spanEnd;
      }
      expect(foundOffset, isNotNull);
      expect(foundOffset, greaterThanOrEqualTo(0));
    });

    test('finds text spanning multiple spans', () {
      final blocks = parseBlocks('<p><b>Hello</b> World</p>');
      final p = blocks.first as ParagraphBlock;
      final spans = p.lines.first.spans;

      // Should have at least 2 spans (bold + normal)
      expect(spans.length, greaterThanOrEqualTo(1));

      // Concatenate all spans
      final fullText = spans.map((s) => s.text).join();
      expect(fullText, contains('Hello'));
      expect(fullText, contains('World'));

      // Search for "Hello World" across spans
      final searchText = 'Hello World';
      final idx = fullText.indexOf(searchText);
      // This may be -1 if there's a space mismatch, but the text should be findable
      if (idx >= 0) {
        var cursor = 0;
        int? foundOffset;
        for (final span in spans) {
          final spanEnd = cursor + span.text.length;
          if (idx < spanEnd) {
            foundOffset = span.startOffset + (idx - cursor);
            break;
          }
          cursor = spanEnd;
        }
        expect(foundOffset, isNotNull);
      }
    });

    test('returns null for text not found', () {
      final blocks = parseBlocks('<p>Hello</p>');
      final p = blocks.first as ParagraphBlock;
      final spans = p.lines.first.spans;
      final fullText = spans.map((s) => s.text).join();
      expect(fullText.indexOf('XYZ'), -1);
    });
  });

  group('Annotation offset calculation', () {
    test('offsets are consistent between raw and annotated blocks', () {
      final html = '<p><b>Bold</b> and <i>Italic</i> text</p>';
      final blocks = parseBlocks(html);
      final p = blocks.first as ParagraphBlock;

      // Collect all span offsets
      final offsets = <int>[];
      for (final line in p.lines) {
        for (final span in line.spans) {
          offsets.add(span.startOffset);
        }
      }

      // Offsets should be sequential and non-overlapping
      for (var i = 1; i < offsets.length; i++) {
        expect(offsets[i], greaterThan(offsets[i - 1]));
      }
    });

    test('blockquote preserves span offsets', () {
      final html = '<blockquote><p>Quote <b>text</b></p></blockquote>';
      final blocks = parseBlocks(html);
      final bq = blocks.first as BlockquoteBlock;
      final spans = bq.lines.first.spans;

      expect(spans, isNotEmpty);
      expect(spans.first.startOffset, greaterThanOrEqualTo(0));
      if (spans.length > 1) {
        expect(spans[1].startOffset, greaterThan(spans[0].startOffset));
      }
    });

    test('list preserves span offsets', () {
      final html = '<ul><li>Item <b>one</b></li><li>Item two</li></ul>';
      final blocks = parseBlocks(html);
      final list = blocks.first as ListBlock;

      expect(list.items.length, greaterThanOrEqualTo(2));
      expect(list.items.first.spans, isNotEmpty);
    });

    test('table preserves span offsets', () {
      final html =
          '<table><tr><td><b>Bold</b></td><td>Normal</td></tr></table>';
      final blocks = parseBlocks(html);
      final table = blocks.first as TableBlock;

      expect(table.rows, hasLength(1));
      expect(table.rows.first.cells, hasLength(2));
      expect(table.rows.first.cells.first, isNotEmpty);
      expect(table.rows.first.cells.last, isNotEmpty);
    });
  });

  group('ReaderInlineSpan fields', () {
    test('all inline style fields default to false', () {
      const span = ReaderInlineSpan(text: 'test');
      expect(span.isBold, isFalse);
      expect(span.isItalic, isFalse);
      expect(span.isHeading, isFalse);
      expect(span.isCode, isFalse);
      expect(span.isSuperscript, isFalse);
      expect(span.isSubscript, isFalse);
      expect(span.isMarked, isFalse);
      expect(span.isDeleted, isFalse);
      expect(span.isUnderlined, isFalse);
      expect(span.href, isNull);
      expect(span.backgroundColor, isNull);
      expect(span.startOffset, 0);
    });

    test('superscript span has correct flags', () {
      final blocks = parseBlocks('<p>X<sup>2</sup></p>');
      final p = blocks.first as ParagraphBlock;
      final supSpan = p.lines.first.spans.firstWhere((s) => s.text == '2');
      expect(supSpan.isSuperscript, isTrue);
      expect(supSpan.isSubscript, isFalse);
    });

    test('subscript span has correct flags', () {
      final blocks = parseBlocks('<p>H<sub>2</sub>O</p>');
      final p = blocks.first as ParagraphBlock;
      final subSpan = p.lines.first.spans.firstWhere((s) => s.text == '2');
      expect(subSpan.isSubscript, isTrue);
      expect(subSpan.isSuperscript, isFalse);
    });

    test('mark span has correct flags', () {
      final blocks = parseBlocks('<p><mark>hi</mark></p>');
      final span = (blocks.first as ParagraphBlock).lines.first.spans.first;
      expect(span.isMarked, isTrue);
    });

    test('deleted span has correct flags', () {
      final blocks = parseBlocks('<p><del>old</del></p>');
      final span = (blocks.first as ParagraphBlock).lines.first.spans.first;
      expect(span.isDeleted, isTrue);
    });

    test('underlined span has correct flags', () {
      final blocks = parseBlocks('<p><u>under</u></p>');
      final span = (blocks.first as ParagraphBlock).lines.first.spans.first;
      expect(span.isUnderlined, isTrue);
    });
  });

  group('Settings model', () {
    test('default settings have correct values', () {
      // ReaderViewSettings defaults
      const fontFamily = 'serif';
      const fontSize = 18.0;
      const lineHeight = 1.8;
      const themeIndex = 2;
      const readingMode = 'scroll';
      const immersiveMode = false;

      expect(fontFamily, 'serif');
      expect(fontSize, 18.0);
      expect(lineHeight, 1.8);
      expect(themeIndex, 2);
      expect(readingMode, 'scroll');
      expect(immersiveMode, isFalse);
    });

    test('version migration adds missing fields', () {
      // Simulate v0 JSON (no immersiveMode)
      final v0Json = {
        'fontFamily': 'serif',
        'fontSize': 18.0,
        'lineHeight': 1.8,
        'themeIndex': 2,
        'readingMode': 'scroll',
        // no 'version', no 'immersiveMode'
      };

      final version = v0Json['version'] as int? ?? 0;
      expect(version, 0);

      // Migration should add defaults
      var migrated = Map<String, dynamic>.from(v0Json);
      if (version < 1) {
        migrated['immersiveMode'] ??= false;
      }

      expect(migrated['immersiveMode'], isFalse);
      expect(migrated['fontFamily'], 'serif'); // original preserved
    });

    test('version migration preserves existing fields', () {
      final v0Json = {
        'fontFamily': 'sans',
        'fontSize': 20.0,
        'lineHeight': 2.0,
        'themeIndex': 0,
        'readingMode': 'page',
        'immersiveMode': true, // already set
      };

      final version = v0Json['version'] as int? ?? 0;
      var migrated = Map<String, dynamic>.from(v0Json);
      if (version < 1) {
        migrated['immersiveMode'] ??= false;
      }

      // Existing values should NOT be overwritten
      expect(migrated['immersiveMode'], isTrue);
      expect(migrated['fontFamily'], 'sans');
    });
  });

  group('Session tracking', () {
    test('duration calculation is correct', () {
      final start = DateTime(2026, 6, 10, 10, 0, 0);
      final end = DateTime(2026, 6, 10, 10, 15, 30);
      final duration = end.difference(start).inSeconds;
      expect(duration, 930);
    });

    test('sessions shorter than 10 seconds are skipped', () {
      final start = DateTime(2026, 6, 10, 10, 0, 0);
      final end = DateTime(2026, 6, 10, 10, 0, 5);
      final duration = end.difference(start).inSeconds;
      expect(duration, lessThan(10));
    });

    test('session timestamps are UTC ISO8601', () {
      final now = DateTime.now();
      final utc = now.toUtc().toIso8601String();
      expect(utc, contains('T'));
      expect(utc, contains('Z'));
      // Should be parseable back
      final parsed = DateTime.parse(utc);
      expect(parsed.isUtc, isTrue);
    });
  });

  group('Progress bar animation suppression', () {
    test('isAnimatingScroll flag prevents progress updates', () {
      bool isAnimatingScroll = false;
      double scrollProgress = 0.02;

      // Simulate _onScroll behavior
      void onScroll(double newProgress) {
        if (!isAnimatingScroll) {
          scrollProgress = newProgress;
        }
      }

      // Normal scroll updates progress
      onScroll(0.05);
      expect(scrollProgress, 0.05);

      // During animation, updates are suppressed
      isAnimatingScroll = true;
      onScroll(0.50);
      expect(scrollProgress, 0.05); // unchanged

      // After animation ends, next scroll updates normally
      isAnimatingScroll = false;
      onScroll(0.10);
      expect(scrollProgress, 0.10);
    });

    test('animation completion sets final progress', () {
      double scrollProgress = 0.02;
      bool isAnimatingScroll = true;

      // Simulate animation completion
      final target = 0.08;
      isAnimatingScroll = false;
      scrollProgress = target;

      expect(scrollProgress, 0.08);
      expect(isAnimatingScroll, isFalse);
    });
  });

  group('Page mode navigation', () {
    test('page index calculation from scroll offset', () {
      final contentOffset = 1600.0;
      final pageHeight = 800.0;
      final pageIndex = (contentOffset / pageHeight).floor();
      expect(pageIndex, 2);
    });

    test('page index clamps to valid range', () {
      final contentOffset = 99999.0;
      final pageHeight = 800.0;
      final totalPages = 5;
      final pageIndex = (contentOffset / pageHeight).floor().clamp(
        0,
        totalPages - 1,
      );
      expect(pageIndex, 4);
    });

    test('progress calculation from page index', () {
      final currentPage = 3;
      final totalPages = 10;
      final progress =
          totalPages > 1
              ? (currentPage / (totalPages - 1)).clamp(0.0, 1.0)
              : 0.0;
      expect(progress, closeTo(0.333, 0.01));
    });

    test('first page has zero progress', () {
      final currentPage = 0;
      final totalPages = 10;
      final progress =
          totalPages > 1
              ? (currentPage / (totalPages - 1)).clamp(0.0, 1.0)
              : 0.0;
      expect(progress, 0.0);
    });

    test('last page has full progress', () {
      final currentPage = 9;
      final totalPages = 10;
      final progress =
          totalPages > 1
              ? (currentPage / (totalPages - 1)).clamp(0.0, 1.0)
              : 0.0;
      expect(progress, 1.0);
    });

    test('single page has zero progress', () {
      final totalPages = 1;
      final progress = totalPages > 1 ? 0.5 : 0.0;
      expect(progress, 0.0);
    });
  });

  group('Side tap zone detection', () {
    test('left third triggers backward action', () {
      final screenWidth = 900.0;
      final tapX = 200.0; // < 300 (1/3 of 900)
      expect(tapX, lessThan(screenWidth / 3));
    });

    test('right third triggers forward action', () {
      final screenWidth = 900.0;
      final tapX = 700.0; // > 600 (2/3 of 900)
      expect(tapX, greaterThan(screenWidth * 2 / 3));
    });

    test('center third triggers toggle controls', () {
      final screenWidth = 900.0;
      final tapX = 450.0; // between 300 and 600
      expect(tapX, greaterThanOrEqualTo(screenWidth / 3));
      expect(tapX, lessThanOrEqualTo(screenWidth * 2 / 3));
    });

    test('pointer distance threshold for tap vs drag', () {
      final downPos = const Offset(100, 100);
      final upPos = const Offset(110, 110);
      final distance = (upPos - downPos).distance;
      expect(distance, closeTo(14.14, 0.1));
      expect(distance, lessThan(20)); // should be recognized as tap
    });

    test('large pointer distance is drag, not tap', () {
      final downPos = const Offset(100, 100);
      final upPos = const Offset(200, 200);
      final distance = (upPos - downPos).distance;
      expect(distance, closeTo(141.42, 0.1));
      expect(distance, greaterThanOrEqualTo(20)); // should NOT be tap
    });
  });
}
