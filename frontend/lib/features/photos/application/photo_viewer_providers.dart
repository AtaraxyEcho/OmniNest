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

/// 按标签查询照片的分页累积状态：滚动加载消费。
class TagPhotosState {
  const TagPhotosState({
    required this.items,
    this.hasMore = false,
    this.isLoadingMore = false,
  });

  final List<PhotoItem> items;
  final bool hasMore;
  final bool isLoadingMore;

  TagPhotosState copyWith({
    List<PhotoItem>? items,
    bool? hasMore,
    bool? isLoadingMore,
  }) {
    return TagPhotosState(
      items: items ?? this.items,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

/// 按标签查询照片：首页 50 条，触底续页按键去重，失败回滚保持可重试。
class PhotosByTagNotifier extends AsyncNotifier<TagPhotosState> {
  PhotosByTagNotifier(this.tag);

  final String tag;
  int _page = 0;

  @override
  Future<TagPhotosState> build() async {
    _page = 0;
    final first = await ref.watch(photoRepositoryProvider).listByTagPage(tag);
    return TagPhotosState(items: first.items, hasMore: first.hasMore);
  }

  Future<void> loadMore() async {
    final current = state.asData?.value;
    if (current == null || !current.hasMore || current.isLoadingMore) {
      return;
    }
    state = AsyncData(current.copyWith(isLoadingMore: true));
    try {
      final next = await ref
          .read(photoRepositoryProvider)
          .listByTagPage(tag, page: _page + 1);
      _page += 1;
      final seen = current.items.map((item) => item.id).toSet();
      final merged = <PhotoItem>[
        ...current.items,
        ...next.items.where((item) => !seen.contains(item.id)),
      ];
      state = AsyncData(TagPhotosState(items: merged, hasMore: next.hasMore));
    } on Object {
      // 失败回滚加载中标志，尾部重试行由视图承载。
      state = AsyncData(current);
    }
  }
}

final photosByTagProvider = AsyncNotifierProvider.autoDispose
    .family<PhotosByTagNotifier, TagPhotosState, String>(
      PhotosByTagNotifier.new,
    );

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
