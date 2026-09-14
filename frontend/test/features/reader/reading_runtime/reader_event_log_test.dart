import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_event_log.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_runtime_diagnostics.dart';

void main() {
  group('ReaderRuntimeEventLog（方案 §103/§126）', () {
    test('环形缓冲容量淘汰并记录丢弃数', () {
      final log = ReaderRuntimeEventLog(capacity: 3);
      for (var i = 0; i < 5; i++) {
        log.emit(
          ReaderRuntimeEvent(
            type: ReaderRuntimeEventType.transactionStarted,
            at: DateTime(2026, 1, 1),
            transactionId: i,
            kind: 'wheel',
          ),
        );
      }
      expect(log.events.length, 3);
      expect(log.droppedCount, 2);
      // 最旧的已淘汰，最新保留。
      expect(log.events.first.transactionId, 2);
      expect(log.events.last.transactionId, 4);
    });

    test('§126 验收格式：事务/位置/几何/进度四类行', () {
      final log = ReaderRuntimeEventLog();
      final at = DateTime(2026);
      expect(
        log.format(
          ReaderRuntimeEvent(
            type: ReaderRuntimeEventType.transactionStarted,
            at: at,
            transactionId: 21,
            kind: 'wheel',
          ),
        ),
        'ReaderTransaction: tx=21 started kind=wheel',
      );
      expect(
        log.format(
          ReaderRuntimeEvent(
            type: ReaderRuntimeEventType.positionResolved,
            at: at,
            transactionId: 21,
            layoutRevision: '1402/88',
            offset: 502.0,
            chapterId: 'chapter_1',
            blockIndex: 1,
            charOffset: 121,
            visualProgress: 0.7449,
          ),
        ),
        'ReaderPosition: tx=21 geometry=1402/88 offset=502.0 '
        'chapter=chapter_1 block=1 char=121 visual=0.7449 logical=null',
      );
      expect(
        log.format(
          ReaderRuntimeEvent(
            type: ReaderRuntimeEventType.geometryCommitted,
            at: at,
            transactionId: 21,
            layoutRevision: '1403/89',
          ),
        ),
        'ReaderGeometry: tx=21 commit geometry=1403/89',
      );
      expect(
        log.format(
          ReaderRuntimeEvent(
            type: ReaderRuntimeEventType.progressPublished,
            at: at,
            transactionId: 21,
            visualProgress: 1.0,
          ),
        ),
        'ReaderProgress: tx=21 visual=1.0000',
      );
      expect(
        log.format(
          ReaderRuntimeEvent(
            type: ReaderRuntimeEventType.transactionCompleted,
            at: at,
            transactionId: 21,
            kind: 'wheel',
          ),
        ),
        'ReaderTransaction: tx=21 completed kind=wheel',
      );
    });
  });
}
