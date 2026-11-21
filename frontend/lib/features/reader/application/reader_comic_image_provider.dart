import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/data/comic_image_provider.dart';
import 'package:omninest/features/reader/domain/comic_models.dart';

/// 漫画图片加载器的应用层入口。
final comicImageLoaderProvider = Provider.autoDispose<ComicImageLoader>((ref) {
  final loader = ComicImageLoader(
    ref.read(readerApiProvider),
    maxCacheBytes: _comicImageCacheBytes(),
  );
  ref.onDispose(loader.invalidateAll);
  return loader;
});

/// 应用层同步读取漫画单页内存字节缓存的便捷入口。
Uint8List? getCachedComicBytesSync(
  WidgetRef ref,
  String itemId,
  String pageId, {
  String sourcePath = '',
}) {
  return ref
      .read(comicImageLoaderProvider)
      .getCachedBytesSync(itemId, pageId, sourcePath: sourcePath);
}

/// 应用层预加载当前页前后邻页图片的便捷入口。
Future<void> preloadComicAdjacentPages(
  WidgetRef ref,
  String itemId,
  List<ComicPage> pages,
  int currentIndex, {
  int before = 2,
  int after = 4,
}) {
  return ref
      .read(comicImageLoaderProvider)
      .preloadAdjacent(
        itemId,
        pages,
        currentIndex,
        before: before,
        after: after,
      );
}

int _comicImageCacheBytes() {
  const mebibyte = 1024 * 1024;
  if (isWebPlatform) {
    return 16 * mebibyte;
  }
  if (isDesktopPlatform) {
    return 64 * mebibyte;
  }
  return 32 * mebibyte;
}
