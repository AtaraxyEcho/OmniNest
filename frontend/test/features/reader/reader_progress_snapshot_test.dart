import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/application/reader_progress_snapshot.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';

void main() {
  group('ReaderProgressSnapshot', () {
    test('normalizes server progress percent to chapter progress', () {
      final snapshot = ReaderProgressSnapshot.fromServer(
        ReaderProgress(
          readerItemId: 'item-1',
          charOffset: 100,
          progressPercent: 20,
          readingMode: 'scroll',
          updatedAt: DateTime(2026),
        ),
      );

      expect(snapshot, isNotNull);
      // V2: server doesn't store chapterId, determined client-side from charOffset
      expect(snapshot.chapterId, '');
      expect(snapshot.charOffset, 100);
      expect(snapshot.bookProgress, 0.2);
      expect(snapshot.mode, 'scroll');
      expect(snapshot.updatedAt, DateTime(2026));
    });

    test('local progress keeps chapter scale out of book scale', () {
      final local = ReaderProgressSnapshot.fromLocal({
        'chapterId': 'chapter-1',
        'chapterProgress': 0.35,
        'charOffset': 120,
        'updatedAt': DateTime(2026, 1, 2).toIso8601String(),
      });

      // 本地行只存章内口径；把 chapterProgress 塞进 bookProgress 会让
      // 回声判定和上报比较跨口径相减。
      expect(local.chapterProgress, 0.35);
      expect(local.bookProgress, isNull);
      expect(local.hasReadableProgress, isTrue);
    });

    test('keeps local progress when it is newer than server progress', () {
      final local = ReaderProgressSnapshot.fromLocal({
        'chapterId': 'chapter-1',
        'chapterProgress': 0.35,
        'charOffset': 120,
        'updatedAt': DateTime(2026, 1, 2).toIso8601String(),
      });
      final server = ReaderProgressSnapshot.fromServer(
        ReaderProgress(
          readerItemId: 'item-1',
          charOffset: 0,
          progressPercent: 10,
          readingMode: 'scroll',
          updatedAt: DateTime(2026, 1),
        ),
      );

      final latest = ReaderProgressSnapshot.latest(local, server);

      expect(latest, same(local));
      expect(latest!.chapterProgress, 0.35);
      expect(latest.charOffset, 120);
    });

    test('uses newer server progress when its timestamp is later', () {
      final local = ReaderProgressSnapshot.fromLocal({
        'chapterId': 'chapter-1',
        'charOffset': 120,
        'updatedAt': DateTime(2026, 1).toIso8601String(),
      });
      final server = ReaderProgressSnapshot.fromServer(
        ReaderProgress(
          readerItemId: 'item-1',
          chapterId: 'chapter-1',
          charOffset: 360,
          progressPercent: 30,
          readingMode: 'page',
          updatedAt: DateTime(2026, 1, 2),
        ),
      );

      final latest = ReaderProgressSnapshot.latest(local, server);

      expect(latest, same(server));
      expect(latest!.charOffset, 360);
      expect(latest.mode, 'page');
    });

    test('carries manifest version from server and local rows', () {
      final server = ReaderProgressSnapshot.fromServer(
        ReaderProgress(
          readerItemId: 'item-1',
          chapterId: 'chapter-1',
          charOffset: 360,
          progressPercent: 30,
          readingMode: 'scroll',
          manifestVersion: 4,
          updatedAt: DateTime(2026),
        ),
      );
      expect(server.manifestVersion, 4);

      final local = ReaderProgressSnapshot.fromLocal({
        'chapterId': 'chapter-1',
        'charOffset': 360,
        'chapterProgress': 0.3,
        'manifestVersion': 4,
        'updatedAt': DateTime(2026).toIso8601String(),
      });
      expect(local.manifestVersion, 4);

      // 旧行没有版本列：null 表示未知，不得被当成版本不一致。
      final legacy = ReaderProgressSnapshot.fromLocal({
        'chapterId': 'chapter-1',
        'charOffset': 360,
        'chapterProgress': 0.3,
        'updatedAt': DateTime(2026).toIso8601String(),
      });
      expect(legacy.manifestVersion, isNull);
    });

    test('resolves continue-reading chapter from progress snapshot', () {
      final chapters = [
        ReaderChapter(id: 'chapter-1', chapterNumber: 1, title: '第一章'),
        ReaderChapter(id: 'chapter-2', chapterNumber: 2, title: '第二章'),
      ];
      final snapshot = ReaderProgressSnapshot(
        chapterId: 'chapter-2',
        bookProgress: 0.2,
      );

      final chapter = ReaderProgressSnapshot.resolveChapter(chapters, snapshot);

      expect(chapter?.id, 'chapter-2');
    });
  });
}
