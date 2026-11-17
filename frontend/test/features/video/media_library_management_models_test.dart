import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/video/domain/movie_models.dart';

void main() {
  test('parses review run and keeps large counters typed', () {
    final run = MediaScanRun.fromJson({
      'id': 'run-1',
      'librarySourceId': 'source-1',
      'generation': 3,
      'selectionRevision': 7,
      'status': 'READY',
      'phase': 'DISCOVERY',
      'candidateCount': 100000,
      'selectedCount': 1234,
    });

    expect(run.reviewable, isTrue);
    expect(run.active, isFalse);
    expect(run.candidateCount, 100000);
    expect(run.selectionRevision, 7);
  });

  test('parses paged semantic tree without raw maps escaping', () {
    final page = MediaPage.fromJson({
      'items': [
        {
          'nodeId': 'SERIES:1',
          'nodeType': 'SERIES',
          'title': 'Example Series',
          'hasChildren': true,
          'childCount': 24,
          'candidateCount': 24,
          'selectedCount': 12,
          'issueCount': 1,
          'selectionState': 'PARTIAL',
        },
      ],
      'page': 0,
      'size': 100,
      'totalElements': 1,
      'totalPages': 1,
    }, MediaScanTreeNode.fromJson);

    expect(page.items, hasLength(1));
    expect(page.items.single.selectionState, 'PARTIAL');
    expect(page.items.single.hasChildren, isTrue);
  });

  test('unavailable video items disable playback semantics', () {
    final item = MovieVideoItem.fromJson({
      'id': 'video-1',
      'fileNodeId': 'file-1',
      'title': 'Missing Movie',
      'availabilityStatus': 'MISSING',
    });

    expect(item.available, isFalse);
    expect(item.availabilityStatus, 'MISSING');
  });
}
