import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_masonry_layout.dart';

PhotoItem _photo(String id, {int? width, int? height}) {
  return PhotoItem(
    id: id,
    fileNodeId: 'file-$id',
    title: id,
    format: 'JPEG',
    fileSize: 1,
    metadataStatus: 'READY',
    favorite: false,
    createdAt: DateTime(2024),
    width: width,
    height: height,
  );
}

void main() {
  group('assignMasonryColumns', () {
    test('按最矮列贪心分配且不丢图', () {
      final photos = [
        for (var i = 0; i < 17; i++)
          _photo('p$i', width: 100, height: i.isEven ? 100 : 200),
      ];
      final tracks = assignMasonryColumns(photos, 3);
      expect(tracks, hasLength(3));
      final ids = [for (final track in tracks) ...track.map((p) => p.id)];
      expect(ids.toSet(), photos.map((p) => p.id).toSet());
      expect(ids, hasLength(photos.length));
    });

    test('缺失尺寸按 1.0 纵横比参与分配', () {
      final photos = [_photo('a'), _photo('b'), _photo('c'), _photo('d')];
      final tracks = assignMasonryColumns(photos, 2);
      expect(tracks[0], hasLength(2));
      expect(tracks[1], hasLength(2));
    });
  });

  group('windowMasonryColumns', () {
    test('按窗口切片且各列内顺序与整表分柱一致', () {
      final photos = [
        for (var i = 0; i < 20; i++) _photo('p$i', width: 1, height: 1),
      ];
      final tracks = assignMasonryColumns(photos, 2);
      final windows = windowMasonryColumns(tracks, windowSize: 3);
      expect(windows, isNotEmpty);

      for (var columnIndex = 0; columnIndex < tracks.length; columnIndex++) {
        final rebuilt = [for (final window in windows) ...window[columnIndex]];
        expect(
          rebuilt.map((p) => p.id).toList(),
          tracks[columnIndex].map((p) => p.id).toList(),
        );
      }

      final allIds = {
        for (final window in windows)
          for (final track in window) ...track.map((p) => p.id),
      };
      expect(allIds, photos.map((p) => p.id).toSet());
    });

    test('短列窗口可为空而不越界', () {
      final tracks = [
        [for (var i = 0; i < 5; i++) _photo('a$i')],
        [_photo('b0')],
      ];
      final windows = windowMasonryColumns(tracks, windowSize: 2);
      expect(windows, hasLength(3));
      expect(windows[0][1], hasLength(1));
      expect(windows[1][1], isEmpty);
      expect(windows[2][0], hasLength(1));
      expect(windows[2][1], isEmpty);
    });
  });
}
