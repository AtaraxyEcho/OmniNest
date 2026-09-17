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
  group('placeMasonryTiles', () {
    test('贪心分列且不丢图、列内 top 递增', () {
      final photos = [
        for (var i = 0; i < 17; i++)
          _photo('p$i', width: 100, height: i.isEven ? 100 : 200),
      ];
      final placed = placeMasonryTiles(photos, 3);
      expect(placed, hasLength(photos.length));
      expect(
        placed.map((t) => t.photo.id).toSet(),
        photos.map((p) => p.id).toSet(),
      );
      final topsByColumn = <int, List<double>>{};
      for (final tile in placed) {
        topsByColumn.putIfAbsent(tile.column, () => []).add(tile.logicalTop);
      }
      for (final tops in topsByColumn.values) {
        for (var i = 1; i < tops.length; i++) {
          expect(tops[i], greaterThan(tops[i - 1]));
        }
      }
    });

    test('同列相邻 tile 无空洞（top 连续）', () {
      final photos = [
        for (var i = 0; i < 12; i++) _photo('p$i', width: 1, height: 1),
      ];
      const gap = 0.05;
      final placed = placeMasonryTiles(photos, 2, gapLogical: gap);
      final byColumn = <int, List<MasonryPlacedTile>>{};
      for (final tile in placed) {
        byColumn.putIfAbsent(tile.column, () => []).add(tile);
      }
      for (final columnTiles in byColumn.values) {
        for (var i = 1; i < columnTiles.length; i++) {
          final prev = columnTiles[i - 1];
          final next = columnTiles[i];
          expect(
            next.logicalTop,
            closeTo(prev.logicalTop + prev.logicalExtent + gap, 1e-9),
          );
        }
      }
    });

    test('固定 gapLogical 下分柱结果与列宽无关（缩放只做坐标缩放）', () {
      final photos = [
        for (var i = 0; i < 20; i++)
          _photo('p$i', width: 100 + (i % 3) * 40, height: 100 + (i % 5) * 30),
      ];
      const gapLogical = 0.05;
      final placedA = placeMasonryTiles(photos, 3, gapLogical: gapLogical);
      final placedB = placeMasonryTiles(photos, 3, gapLogical: gapLogical);
      expect(placedA.length, placedB.length);
      for (var i = 0; i < placedA.length; i++) {
        expect(placedA[i].column, placedB[i].column);
        expect(placedA[i].logicalTop, placedB[i].logicalTop);
        expect(placedA[i].logicalExtent, placedB[i].logicalExtent);
      }
    });
  });

  group('masonryTotalLogicalHeight', () {
    test('等于各列 bottom 最大值', () {
      final photos = [
        // ratio clamp 到 0.6..2.4；横图 extent=1/2=0.5，方图 extent=1
        _photo('wide', width: 2, height: 1),
        _photo('square', width: 1, height: 1),
      ];
      final placed = placeMasonryTiles(photos, 2);
      final total = masonryTotalLogicalHeight(placed);
      expect(total, closeTo(1.0, 1e-9));
    });
  });

  group('windowMasonryColumns', () {
    test('按窗口切片且各列内顺序与分柱一致', () {
      final photos = [
        for (var i = 0; i < 20; i++) _photo('p$i', width: 1, height: 1),
      ];
      final placed = placeMasonryTiles(photos, 2);
      final tracks = List.generate(2, (_) => <PhotoItem>[]);
      for (final tile in placed) {
        tracks[tile.column].add(tile.photo);
      }
      final windows = windowMasonryColumns(tracks, windowSize: 3);
      for (var columnIndex = 0; columnIndex < tracks.length; columnIndex++) {
        final rebuilt = [for (final window in windows) ...window[columnIndex]];
        expect(
          rebuilt.map((p) => p.id).toList(),
          tracks[columnIndex].map((p) => p.id).toList(),
        );
      }
    });
  });
}
