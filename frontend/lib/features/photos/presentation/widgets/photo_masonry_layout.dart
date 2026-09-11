import 'package:omninest/features/photos/domain/photo.dart';

/// 照片纵横比：缺失或非法尺寸回退 1.0，并按设计稿夹紧范围。
double photoMasonryAspectRatio(PhotoItem photo) {
  final width = photo.width;
  final height = photo.height;
  if (width == null || height == null || width <= 0 || height <= 0) {
    return 1.0;
  }
  return (width / height).clamp(0.6, 2.4);
}

/// 瀑布流中一张图的逻辑布局：逻辑高以「列宽 = 1」为单位。
class MasonryPlacedTile {
  const MasonryPlacedTile({
    required this.photo,
    required this.column,
    required this.logicalTop,
    required this.logicalExtent,
  });

  final PhotoItem photo;
  final int column;
  final double logicalTop;
  final double logicalExtent;
}

/// 将照片按纵横比贪心分配到最矮列，并计算连续列坐标。
///
/// [gapLogical] 为图格间距与列宽之比（例如 10px 间距、200px 列宽 → 0.05），
/// 计入高度累计，保证同列相邻 tile 紧贴且跨任意切片都不出现空洞。
List<MasonryPlacedTile> placeMasonryTiles(
  List<PhotoItem> photos,
  int columns, {
  double gapLogical = 0,
}) {
  final trackCount = columns.clamp(1, 12);
  final tops = List.filled(trackCount, 0.0);
  final placed = <MasonryPlacedTile>[];
  for (final photo in photos) {
    final extent = 1 / photoMasonryAspectRatio(photo);
    var shortest = 0;
    for (var i = 1; i < trackCount; i++) {
      if (tops[i] < tops[shortest]) {
        shortest = i;
      }
    }
    placed.add(
      MasonryPlacedTile(
        photo: photo,
        column: shortest,
        logicalTop: tops[shortest],
        logicalExtent: extent,
      ),
    );
    // 最后一张后不再追加间距，避免总高度虚高一截。
    tops[shortest] += extent + gapLogical;
  }
  return placed;
}

/// 全表瀑布流总逻辑高度。
double masonryTotalLogicalHeight(List<MasonryPlacedTile> tiles) {
  var maxBottom = 0.0;
  for (final tile in tiles) {
    final bottom = tile.logicalTop + tile.logicalExtent;
    if (bottom > maxBottom) {
      maxBottom = bottom;
    }
  }
  return maxBottom;
}

/// 将已分柱结果按「每列最多 [windowSize] 张」切成垂直窗口。
///
/// 仅用于测试与兼容；生产渲染请使用 [placeMasonryTiles] + 视口裁剪，
/// 避免按行窗口切片导致同列在窗口边界出现高度空洞。
List<List<List<PhotoItem>>> windowMasonryColumns(
  List<List<PhotoItem>> tracks, {
  required int windowSize,
}) {
  if (tracks.isEmpty || windowSize <= 0) {
    return const <List<List<PhotoItem>>>[];
  }
  var maxLen = 0;
  for (final track in tracks) {
    if (track.length > maxLen) {
      maxLen = track.length;
    }
  }
  if (maxLen == 0) {
    return const <List<List<PhotoItem>>>[];
  }
  final windows = <List<List<PhotoItem>>>[];
  for (var start = 0; start < maxLen; start += windowSize) {
    final end = start + windowSize;
    windows.add([
      for (final track in tracks)
        [for (var i = start; i < end && i < track.length; i++) track[i]],
    ]);
  }
  return windows;
}
