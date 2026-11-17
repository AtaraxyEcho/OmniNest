import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/data/comic_image_provider.dart';

/// 漫画图片加载器的应用层入口。
final comicImageLoaderProvider = Provider.autoDispose<ComicImageLoader>((ref) {
  final loader = ComicImageLoader(
    ref.read(readerApiProvider),
    maxCacheBytes: _comicImageCacheBytes(),
  );
  ref.onDispose(loader.invalidateAll);
  return loader;
});

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
