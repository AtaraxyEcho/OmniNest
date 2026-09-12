import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/photos/application/photo_repository_providers.dart';
import 'package:omninest/features/photos/domain/photo.dart';

/// 照片详情页信息面板的展开状态；在上一张/下一张切换间保持。
class PhotoInfoPanelVisibleNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

final photoInfoPanelVisibleProvider =
    NotifierProvider<PhotoInfoPanelVisibleNotifier, bool>(
      PhotoInfoPanelVisibleNotifier.new,
    );

/// 用户的标签清单（用于标签视图芯片）。
final photoTagsProvider = FutureProvider.autoDispose<List<String>>((ref) {
  return ref.watch(photoRepositoryProvider).listTags();
});

/// 按标签查询的照片列表。
final photosByTagProvider = FutureProvider.autoDispose
    .family<List<PhotoItem>, String>((ref, tag) {
      return ref.watch(photoRepositoryProvider).listByTag(tag);
    });

/// 照片详情页幻灯片播放状态；跨上一张/下一张路由替换保持，
/// 由详情页在路由真实退出（关闭/系统返回）时复位为暂停。
class PhotoSlideshowPlayingNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void start() => state = true;

  void stop() => state = false;
}

final photoSlideshowPlayingProvider =
    NotifierProvider<PhotoSlideshowPlayingNotifier, bool>(
      PhotoSlideshowPlayingNotifier.new,
    );
