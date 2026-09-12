import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/photos/domain/photo.dart';

/// 浏览来源类型：锚定幻灯片等播放集合的业务数据源。
enum PhotoBrowseSource { library, favorites, album, timeline, locations, tag }

/// 当前浏览的照片序列与来源：详情页的上一张/下一张与幻灯片范围来源。
///
/// 由各浏览视图（全部照片、收藏、时间线、影集详情等）在用户打开照片时写入；
/// 序列为该入口对应的完整业务集合（大集合由幻灯片按需分页补齐）。
class PhotoBrowseScope {
  const PhotoBrowseScope({
    this.photos = const [],
    this.source = PhotoBrowseSource.library,
    this.sourceKey,
  });

  final List<PhotoItem> photos;
  final PhotoBrowseSource source;

  /// 来源限定键：影集=影集 ID，标签=标签名，时间线=年月范围；其余为空。
  final String? sourceKey;

  bool contains(String photoId) => photos.any((p) => p.id == photoId);
}

class PhotoBrowseScopeNotifier extends Notifier<PhotoBrowseScope> {
  @override
  PhotoBrowseScope build() => const PhotoBrowseScope();

  void set(
    List<PhotoItem> photos,
    PhotoBrowseSource source, {
    String? sourceKey,
  }) {
    state = PhotoBrowseScope(
      photos: List.unmodifiable(photos),
      source: source,
      sourceKey: sourceKey,
    );
  }
}

final photoBrowseScopeProvider =
    NotifierProvider<PhotoBrowseScopeNotifier, PhotoBrowseScope>(
      PhotoBrowseScopeNotifier.new,
    );
