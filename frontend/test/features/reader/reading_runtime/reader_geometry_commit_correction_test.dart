import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_geometry_commit.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_geometry_store.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_continuous_scroll_controller.dart';

import 'geometry_fixtures.dart';

void main() {
  group('ReaderGeometryCommit.computeAnchorCorrection（方案 §38/§78 位移合成）', () {
    test('图片重测高后按块内比例保持，返回位移量而非绝对目标', () {
      final oldGeometry = snapshotFor([entryWithImage(id: 'c1')]);
      final candidate = snapshotFor([
        entryWithImage(id: 'c1', imageHeight: 800),
      ]);

      // 锚点在图片中部：旧布局 contentY = 36(章头) + 100(文本) + 300 = 436。
      const anchor = VisualAnchor(
        chapterId: 'c1',
        blockIndex: 1,
        offsetInBlock: 300,
      );
      final shift = const ReaderGeometryCommit().computeAnchorCorrection(
        oldGeometry: oldGeometry,
        candidate: candidate,
        anchor: anchor,
        anchorContentY: 436,
      );

      // 新布局图片中部 = 36 + 100 + 400 = 536 → 位移 +100。
      expect(shift, closeTo(100, 0.5));
    });

    test('锚点章在候选几何中缺失时返回 null（调用方回退高度差补偿）', () {
      final oldGeometry = snapshotFor([
        textEntry(id: 'c1', heights: const [100, 200, 300]),
      ]);
      final candidate = snapshotFor([
        textEntry(id: 'c2', heights: const [100, 200, 300]),
      ]);

      const anchor = VisualAnchor(
        chapterId: 'c1',
        blockIndex: 0,
        offsetInBlock: 50,
      );
      final shift = const ReaderGeometryCommit().computeAnchorCorrection(
        oldGeometry: oldGeometry,
        candidate: candidate,
        anchor: anchor,
        anchorContentY: 436,
      );

      expect(shift, isNull);
    });
  });

  group('ReaderGeometryStore 产线回路（方案 §13/§42）', () {
    test('builder 输出经 publishCandidate→commitCandidate 成为 Live', () {
      final store = ReaderGeometryStore();
      final v0 = snapshotFor([
        textEntry(id: 'c1', heights: const [100, 200, 300]),
      ]);

      // 未提交前 Live 为空：requireLive 视为编程错误。
      expect(() => store.requireLive(), throwsStateError);

      store.publishCandidate(v0);
      expect(store.commitCandidate(), isTrue);
      expect(store.live!.revision, v0.revision);

      // 重建（测高替换）后新 Candidate 在下一边界提交。
      final v1 = snapshotFor([
        textEntry(id: 'c1', heights: const [150, 300, 450]),
      ]);
      store.publishCandidate(v1);
      expect(store.candidate!.revision, v1.revision);
      expect(store.live!.revision, v0.revision);
      store.commitCandidate();
      expect(store.live!.revision, v1.revision);
    });
  });
}
