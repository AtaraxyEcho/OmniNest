import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_page_mixin.dart';

/// 同章进度快照的取舍判定。
///
/// 旧实现无条件丢弃所有同章快照，用来挡住「本机保存→服务端回灌→把用户
/// 拉回保存点」，代价是跨设备更靠前的同章进度也一并丢掉，续读只认章切换。
/// 判定改成方向性的：只有明显超前于本机已知位置的快照才施加。
void main() {
  group('isStaleSameChapterSnapshot', () {
    test('本机已保存位置的回灌是陈旧副本', () {
      // 实机日志场景：tracked=1011，回灌 767 把用户拉回封面方向。
      expect(
        isStaleSameChapterSnapshot(
          snapshotChapterId: 'chapter_3',
          snapshotCharOffset: 767,
          trackedChapterId: 'chapter_3',
          trackedCharOffset: 1011,
          ownSavedChapterId: 'chapter_3',
          ownSavedCharOffset: 1011,
        ),
        isTrue,
      );
    });

    test('跨设备更靠前的同章进度必须施加', () {
      expect(
        isStaleSameChapterSnapshot(
          snapshotChapterId: 'chapter_3',
          snapshotCharOffset: 4000,
          trackedChapterId: 'chapter_3',
          trackedCharOffset: 1000,
          ownSavedChapterId: 'chapter_3',
          ownSavedCharOffset: 1000,
        ),
        isFalse,
      );
    });

    test('容差内的同位回灌仍算陈旧', () {
      expect(
        isStaleSameChapterSnapshot(
          snapshotChapterId: 'chapter_3',
          snapshotCharOffset: 1060,
          trackedChapterId: 'chapter_3',
          trackedCharOffset: 1011,
          ownSavedChapterId: null,
          ownSavedCharOffset: 0,
        ),
        isTrue,
      );
    });

    test('超出容差的推进不是陈旧', () {
      expect(
        isStaleSameChapterSnapshot(
          snapshotChapterId: 'chapter_3',
          snapshotCharOffset: 1100,
          trackedChapterId: 'chapter_3',
          trackedCharOffset: 1011,
          ownSavedChapterId: null,
          ownSavedCharOffset: 0,
        ),
        isFalse,
      );
    });

    test('开书首载无记账时照常施加', () {
      expect(
        isStaleSameChapterSnapshot(
          snapshotChapterId: 'chapter_3',
          snapshotCharOffset: 5000,
          trackedChapterId: '',
          trackedCharOffset: 0,
          ownSavedChapterId: null,
          ownSavedCharOffset: 0,
        ),
        isFalse,
      );
    });

    test('异章快照不由本判定处理', () {
      expect(
        isStaleSameChapterSnapshot(
          snapshotChapterId: 'chapter_4',
          snapshotCharOffset: 10,
          trackedChapterId: 'chapter_3',
          trackedCharOffset: 9000,
          ownSavedChapterId: 'chapter_3',
          ownSavedCharOffset: 9000,
        ),
        isFalse,
      );
    });

    test('切章后记账归零不被旧章位置挡住', () {
      expect(
        isStaleSameChapterSnapshot(
          snapshotChapterId: 'chapter_4',
          snapshotCharOffset: 300,
          trackedChapterId: 'chapter_4',
          trackedCharOffset: 0,
          ownSavedChapterId: 'chapter_3',
          ownSavedCharOffset: 9000,
        ),
        isFalse,
      );
    });
  });

  group('isProgressOffsetVersionMismatch', () {
    test('版本变化后字符偏移不再可比', () {
      expect(
        isProgressOffsetVersionMismatch(snapshotVersion: 3, currentVersion: 5),
        isTrue,
      );
    });

    test('任一版本未知时不做降级', () {
      // 历史进度行没有版本列；把 null 当成不一致会让所有老用户的
      // 精确定位一次性失效，只能靠章首恢复。
      expect(
        isProgressOffsetVersionMismatch(
          snapshotVersion: null,
          currentVersion: 5,
        ),
        isFalse,
      );
      expect(
        isProgressOffsetVersionMismatch(
          snapshotVersion: 3,
          currentVersion: null,
        ),
        isFalse,
      );
    });

    test('版本一致时保持精确定位', () {
      expect(
        isProgressOffsetVersionMismatch(snapshotVersion: 5, currentVersion: 5),
        isFalse,
      );
    });
  });
}
