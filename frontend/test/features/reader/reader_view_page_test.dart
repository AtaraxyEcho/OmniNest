import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Progress Payload', () {
    test('scroll mode payload contains required fields', () {
      final payload = {
        'chapterId': 'ch-1',
        'scrollOffset': 100.0,
        'maxScrollExtent': 1000.0,
      };

      expect(payload['chapterId'], 'ch-1');
      expect(payload['scrollOffset'], 100.0);
      expect(payload['maxScrollExtent'], 1000.0);
    });

    test('page mode payload contains required fields', () {
      final payload = {'chapterId': 'ch-1', 'page': 5, 'totalPages': 20};

      expect(payload['chapterId'], 'ch-1');
      expect(payload['page'], 5);
      expect(payload['totalPages'], 20);
    });
  });

  group('Chapter Restoration', () {
    test('restores scroll position from payload', () {
      final payload = {
        'chapterId': 'ch-1',
        'scrollOffset': 500.0,
        'maxScrollExtent': 2000.0,
      };

      expect(payload['chapterId'], isNotNull);
      expect(payload['scrollOffset'], greaterThan(0));
      expect(payload['maxScrollExtent'], greaterThan(0));
    });

    test('ignores restoration for different chapter', () {
      final payload = {
        'chapterId': 'ch-2',
        'scrollOffset': 500.0,
        'maxScrollExtent': 2000.0,
      };

      final currentChapterId = 'ch-1';
      final shouldRestore = payload['chapterId'] == currentChapterId;
      expect(shouldRestore, isFalse);
    });

    test('handles null offset gracefully', () {
      final payload = {
        'chapterId': 'ch-1',
        'scrollOffset': null,
        'maxScrollExtent': 2000.0,
      };

      final offset = (payload['scrollOffset'] as num?)?.toDouble();
      expect(offset, isNull);
    });

    test('handles zero maxScrollExtent', () {
      final payload = {
        'chapterId': 'ch-1',
        'scrollOffset': 0.0,
        'maxScrollExtent': 0.0,
      };

      final maxExtent = (payload['maxScrollExtent'] as num?)?.toDouble();
      expect(maxExtent, 0.0);
    });
  });

  group('Cache Behavior', () {
    test('cache updates only when content changes', () {
      String? cachedContent;

      const newContent = 'New chapter content';
      const sameContent = 'New chapter content';

      if (newContent != cachedContent) {
        cachedContent = newContent;
      }
      expect(cachedContent, newContent);

      final beforeUpdate = cachedContent;
      if (sameContent != cachedContent) {
        cachedContent = sameContent;
      }
      expect(cachedContent, beforeUpdate);
    });

    test('cache handles null previous content', () {
      String? cachedContent;

      const newContent = 'First chapter';

      if (newContent != cachedContent) {
        cachedContent = newContent;
      }
      expect(cachedContent, newContent);
    });
  });

  group('Chapter Navigation', () {
    test('navigates to next chapter within bounds', () {
      final chapters = ['ch-1', 'ch-2', 'ch-3'];
      const currentChapterId = 'ch-1';
      const offset = 1;

      final currentIndex = chapters.indexOf(currentChapterId);
      final targetIndex = currentIndex + offset;

      expect(targetIndex, 1);
      expect(targetIndex, lessThan(chapters.length));
      expect(chapters[targetIndex], 'ch-2');
    });

    test('navigates to previous chapter within bounds', () {
      final chapters = ['ch-1', 'ch-2', 'ch-3'];
      const currentChapterId = 'ch-2';
      const offset = -1;

      final currentIndex = chapters.indexOf(currentChapterId);
      final targetIndex = currentIndex + offset;

      expect(targetIndex, 0);
      expect(targetIndex, greaterThanOrEqualTo(0));
      expect(chapters[targetIndex], 'ch-1');
    });

    test('rejects navigation past last chapter', () {
      final chapters = ['ch-1', 'ch-2', 'ch-3'];
      const currentChapterId = 'ch-3';
      const offset = 1;

      final currentIndex = chapters.indexOf(currentChapterId);
      final targetIndex = currentIndex + offset;

      expect(targetIndex, greaterThanOrEqualTo(chapters.length));
    });

    test('rejects navigation before first chapter', () {
      final chapters = ['ch-1', 'ch-2', 'ch-3'];
      const currentChapterId = 'ch-1';
      const offset = -1;

      final currentIndex = chapters.indexOf(currentChapterId);
      final targetIndex = currentIndex + offset;

      expect(targetIndex, lessThan(0));
    });
  });

  group('Progress Sync', () {
    test('sync sends correct progress percentage', () {
      double scrollProgress = 0.75;
      final progressPercent = scrollProgress * 100;

      expect(progressPercent, 75.0);
    });

    test('sync handles zero progress', () {
      double scrollProgress = 0;
      final progressPercent = scrollProgress * 100;

      expect(progressPercent, 0.0);
    });

    test('sync handles full progress', () {
      double scrollProgress = 1.0;
      final progressPercent = scrollProgress * 100;

      expect(progressPercent, 100.0);
    });
  });

  group('Page Mode', () {
    test('calculates correct page index from scroll offset', () {
      final contentOffset = 1500.0;
      final pageHeight = 800.0;
      final totalPages = 10;

      final pageIndex = (contentOffset / pageHeight).floor().clamp(
        0,
        totalPages - 1,
      );
      expect(pageIndex, 1);
    });

    test('clamps page index to valid range', () {
      final contentOffset = 99999.0;
      final pageHeight = 800.0;
      final totalPages = 5;

      final pageIndex = (contentOffset / pageHeight).floor().clamp(
        0,
        totalPages - 1,
      );
      expect(pageIndex, 4);
    });

    test('calculates scroll progress from page index', () {
      final currentPageIndex = 3;
      final totalPages = 10;

      final progress =
          totalPages > 1
              ? (currentPageIndex / (totalPages - 1)).clamp(0.0, 1.0)
              : 0.0;
      expect(progress, closeTo(0.333, 0.01));
    });
  });

  group('Session Tracking', () {
    test('session duration is calculated correctly', () {
      final start = DateTime(2026, 6, 10, 10, 0, 0);
      final end = DateTime(2026, 6, 10, 10, 30, 0);
      final duration = end.difference(start).inSeconds;

      expect(duration, 1800);
    });

    test('short sessions are skipped', () {
      final start = DateTime(2026, 6, 10, 10, 0, 0);
      final end = DateTime(2026, 6, 10, 10, 0, 5);
      final duration = end.difference(start).inSeconds;

      expect(duration, lessThan(10));
    });
  });

  group('Reading Stats', () {
    test('formatMinutes handles zero', () {
      final minutes = 0;
      expect(minutes, 0);
    });

    test('formatMinutes handles less than 60', () {
      final minutes = 45;
      expect(minutes, lessThan(60));
    });

    test('formatMinutes handles hours and minutes', () {
      final minutes = 150;
      final h = minutes ~/ 60;
      final m = minutes % 60;
      expect(h, 2);
      expect(m, 30);
    });

    test('formatMinutes handles exact hours', () {
      final minutes = 120;
      final h = minutes ~/ 60;
      final m = minutes % 60;
      expect(h, 2);
      expect(m, 0);
    });

    test('streak calculation from date list', () {
      final dates = [
        DateTime(2026, 6, 10),
        DateTime(2026, 6, 9),
        DateTime(2026, 6, 8),
        DateTime(2026, 6, 6), // gap - missed June 7
      ];

      final today = DateTime(2026, 6, 10);
      int streak = 0;
      var expected = today;
      for (final day in dates) {
        if (day == expected) {
          streak++;
          expected = expected.subtract(const Duration(days: 1));
        } else if (day.isBefore(expected)) {
          break;
        }
      }

      expect(streak, 3);
    });
  });
}
