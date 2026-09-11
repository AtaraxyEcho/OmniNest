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

/// 将照片按纵横比贪心分配到最矮列，复刻 CSS columns 顺序铺排。
///
/// 仅在列表引用或列数变化时调用；返回与 [columns] 等长的列数组。
List<List<PhotoItem>> assignMasonryColumns(
  List<PhotoItem> photos,
  int columns,
) {
  final trackCount = columns.clamp(1, 12);
  final tracks = List.generate(trackCount, (_) => <PhotoItem>[]);
  final trackHeights = List.filled(trackCount, 0.0);
  for (final photo in photos) {
    final ratio = photoMasonryAspectRatio(photo);
    var shortest = 0;
    for (var i = 1; i < trackHeights.length; i++) {
      if (trackHeights[i] < trackHeights[shortest]) {
        shortest = i;
      }
    }
    tracks[shortest].add(photo);
    trackHeights[shortest] += 1 / ratio;
  }
  return tracks;
}

/// 将已分柱结果按「每列最多 [windowSize] 张」切成垂直窗口。
///
/// 窗口 i 同时截取各列的第 i 段，保持列内相对顺序与跨窗口的列布局连续。
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
