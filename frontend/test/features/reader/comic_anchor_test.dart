import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/domain/comic_anchor.dart';

void main() {
  group('ComicAnchor', () {
    late ComicAnchor anchor;

    setUp(() {
      anchor = const ComicAnchor(
        pageId: 'page-001',
        pageIndex: 5,
        pageFingerprint: 'abc123',
        sourceId: 'source-1',
        intraPageOffset: 0.3,
        manifestVersion: 2,
      );
    });

    group('withIntraPageOffset', () {
      test('creates copy with new offset', () {
        final updated = anchor.withIntraPageOffset(0.7);
        expect(updated.intraPageOffset, 0.7);
      });

      test('preserves all other fields', () {
        final updated = anchor.withIntraPageOffset(0.7);
        expect(updated.pageId, 'page-001');
        expect(updated.pageIndex, 5);
        expect(updated.pageFingerprint, 'abc123');
        expect(updated.sourceId, 'source-1');
        expect(updated.manifestVersion, 2);
      });

      test('does not mutate original', () {
        anchor.withIntraPageOffset(0.9);
        expect(anchor.intraPageOffset, 0.3);
      });
    });

    group('toString', () {
      test('produces readable output with pageId and pageIndex', () {
        final str = anchor.toString();
        expect(str, contains('pageId=page-001'));
        expect(str, contains('pageIndex=5'));
      });

      test('includes intra offset with 3 decimal places', () {
        final str = anchor.toString();
        expect(str, contains('intra=0.300'));
      });
    });

    group('constructor defaults', () {
      test('intraPageOffset defaults to 0.0', () {
        const minimal = ComicAnchor(pageId: 'p1', pageIndex: 0);
        expect(minimal.intraPageOffset, 0.0);
      });

      test('manifestVersion defaults to 1', () {
        const minimal = ComicAnchor(pageId: 'p1', pageIndex: 0);
        expect(minimal.manifestVersion, 1);
      });

      test('optional fields default to null', () {
        const minimal = ComicAnchor(pageId: 'p1', pageIndex: 0);
        expect(minimal.pageFingerprint, isNull);
        expect(minimal.sourceId, isNull);
      });
    });
  });
}
