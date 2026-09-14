import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_geometry_store.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_scroll_geometry_snapshot.dart';

import 'geometry_fixtures.dart';

ReaderGeometrySnapshot _snapshot(int revision, double lastHeight) {
  return snapshotFor([
    textEntry(id: 'c1', heights: [100, lastHeight, lastHeight + 100]),
  ]).fromRevision(revision);
}

extension on ReaderGeometrySnapshot {
  /// 以指定版本号重建等价快照（测试 Candidate 版本序）。
  ReaderGeometrySnapshot fromRevision(int revision) {
    return ReaderGeometrySnapshot(
      revision: revision,
      chapterIds: chapterIds,
      chapters: chapters,
    );
  }
}

void main() {
  group('ReaderGeometryStore（方案 §13-§14/§119）', () {
    test('requireLive 未初始化时抛 StateError', () {
      final store = ReaderGeometryStore();
      expect(() => store.requireLive(), throwsStateError);
    });

    test('commitCandidate 提交后 Candidate 清空；无 Candidate 返回 false', () {
      final store = ReaderGeometryStore();
      expect(store.commitCandidate(), isFalse);
      store.publishCandidate(_snapshot(100, 200));
      store.publishCandidate(_snapshot(103, 260));
      expect(store.candidate!.revision, 103);
      expect(store.commitCandidate(), isTrue);
      expect(store.live!.revision, 103);
      expect(store.candidate, isNull);
      expect(store.requireLive().revision, 103);
      expect(store.commitCandidate(), isFalse);
    });

    test('Candidate 乱序到达：旧版本被丢弃（方案 §119）', () {
      final store = ReaderGeometryStore();
      store.publishCandidate(_snapshot(103, 260));
      store.publishCandidate(_snapshot(101, 180));
      expect(store.candidate!.revision, 103);
      // 更新版本正常替换。
      store.publishCandidate(_snapshot(104, 280));
      expect(store.candidate!.revision, 104);
    });

    test('discardCandidate 丢弃待提交几何', () {
      final store = ReaderGeometryStore();
      store.publishCandidate(_snapshot(100, 200));
      store.discardCandidate();
      expect(store.candidate, isNull);
      expect(store.live, isNull);
    });
  });
}
