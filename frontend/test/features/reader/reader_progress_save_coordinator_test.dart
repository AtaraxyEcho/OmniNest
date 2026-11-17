import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/application/reader_progress_save_coordinator.dart';
import 'package:omninest/features/reader/application/reader_progress_snapshot.dart';

ReaderProgressSnapshot _snapshot(int charOffset) => ReaderProgressSnapshot(
  chapterId: 'chapter_1',
  charOffset: charOffset,
  chapterProgress: charOffset / 10000,
);

void main() {
  group('ReaderProgressSaveCoordinator', () {
    test('连续滚动不停顿时也必须在 maxWait 落盘', () {
      fakeAsync((async) {
        final written = <int>[];
        final coordinator = ReaderProgressSaveCoordinator(
          writer: (snapshot) async {
            written.add(snapshot.charOffset);
          },
        );
        // 每 200ms 一次读数，永远不给 900ms 防抖窗口走完。
        for (var offset = 200; offset <= 3000; offset += 200) {
          coordinator.schedule(_snapshot(offset));
          async.elapse(const Duration(milliseconds: 200));
        }
        expect(written, isNotEmpty, reason: '连续滚动期间必须周期性落盘，否则关标签页整段进度丢失');
        async.elapse(const Duration(seconds: 2));
        expect(written.last, 3000);
      });
    });

    test('短停顿仍按防抖合并为一次写入', () {
      fakeAsync((async) {
        final written = <int>[];
        final coordinator = ReaderProgressSaveCoordinator(
          writer: (snapshot) async {
            written.add(snapshot.charOffset);
          },
        );
        coordinator.schedule(_snapshot(100));
        async.elapse(const Duration(milliseconds: 300));
        coordinator.schedule(_snapshot(120));
        async.elapse(const Duration(milliseconds: 1200));
        expect(written, [120]);
      });
    });

    test('maxWait 到点写入后重新起算等待窗口', () {
      fakeAsync((async) {
        final written = <int>[];
        final coordinator = ReaderProgressSaveCoordinator(
          writer: (snapshot) async {
            written.add(snapshot.charOffset);
          },
        );
        // 9 秒不间断滚动，按 3 秒上限应至少落盘 3 次。
        for (var step = 0; step < 45; step++) {
          coordinator.schedule(_snapshot(200 * (step + 1)));
          async.elapse(const Duration(milliseconds: 200));
        }
        expect(written.length, greaterThanOrEqualTo(3));
      });
    });

    test('写失败不丢位置：dispose 续写失败的快照', () {
      fakeAsync((async) {
        final written = <int>[];
        var attempts = 0;
        final coordinator = ReaderProgressSaveCoordinator(
          writer: (snapshot) async {
            attempts++;
            if (attempts == 1) {
              throw Exception('disk busy');
            }
            written.add(snapshot.charOffset);
          },
        );
        coordinator.schedule(_snapshot(500));
        async.elapse(const Duration(milliseconds: 1200));
        expect(attempts, 1);
        coordinator.dispose();
        async.flushMicrotasks();
        expect(attempts, 2);
        expect(written, [500]);
      });
    });

    test('最后一次 schedule 决定落盘内容', () {
      fakeAsync((async) {
        final written = <int>[];
        final coordinator = ReaderProgressSaveCoordinator(
          writer: (snapshot) async {
            written.add(snapshot.charOffset);
          },
        );
        coordinator.schedule(_snapshot(300));
        coordinator.schedule(_snapshot(9000));
        coordinator.dispose();
        async.flushMicrotasks();
        expect(written, [9000]);
      });
    });
  });
}
