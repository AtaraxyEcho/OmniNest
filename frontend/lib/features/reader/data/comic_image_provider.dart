import 'dart:collection';
import 'dart:typed_data';

import 'package:omninest/features/reader/data/reader_api.dart';
import 'package:omninest/features/reader/domain/comic_models.dart';
import 'package:omninest/core/config/file_size_thresholds.dart';

/// 漫画图片加载服务。
///
/// 从后端 page API 获取图片，并使用内存 LRU 缓存。
///
/// 缓存按字节预算淘汰，并合并同一页面的并发请求。
class ComicImageLoader {
  ComicImageLoader(
    this._api, {
    this.maxCacheBytes = FileSizeThresholds.readerImageCacheMaxBytes,
  }) : assert(maxCacheBytes >= 0);

  final ReaderApi _api;

  /// 缓存字节上限。
  final int maxCacheBytes;

  /// 内存缓存：页面复合键 -> 图片字节。
  final LinkedHashMap<String, Uint8List> _memoryCache =
      LinkedHashMap<String, Uint8List>();
  final Map<String, Future<Uint8List?>> _inFlight = {};
  int _currentBytes = 0;

  /// 获取指定页面的图片字节。
  ///
  /// 优先从内存缓存读取。
  /// 后端 manifest 是唯一真相源，图片也只通过 pageId 按需读取。
  Future<Uint8List?> getImage(
    String itemId,
    String sourcePath, {
    String? pageId,
  }) async {
    final cacheKey = _cacheKey(itemId, sourcePath, pageId);
    final cached = _takeCached(cacheKey);
    if (cached != null) {
      return cached;
    }

    if (pageId == null) {
      return null;
    }

    final pending = _inFlight[cacheKey];
    if (pending != null) {
      return pending;
    }

    final request = _fetchImage(pageId);
    _inFlight[cacheKey] = request;
    try {
      final image = await request;
      if (image != null && identical(_inFlight[cacheKey], request)) {
        _putCache(cacheKey, image);
      }
      return image;
    } finally {
      if (identical(_inFlight[cacheKey], request)) {
        _inFlight.remove(cacheKey);
      }
    }
  }

  /// 批量预加载指定页面（用于前后预加载）。
  ///
  /// 优先从后端 page API 获取，限制并发为 3。
  Future<void> preloadImages(String itemId, List<ComicPage> pages) async {
    final toLoad =
        pages.where((page) {
          final key = _cacheKey(itemId, page.sourcePath, page.id);
          return !_memoryCache.containsKey(key) && !_inFlight.containsKey(key);
        }).toList();
    if (toLoad.isEmpty) {
      return;
    }

    // 限制并发为 3，避免服务器压力
    const concurrency = 3;
    for (var i = 0; i < toLoad.length; i += concurrency) {
      final batch = toLoad.sublist(
        i,
        (i + concurrency).clamp(0, toLoad.length),
      );
      await Future.wait(
        batch.map(
          (page) => getImage(
            itemId,
            page.sourcePath,
            pageId: page.id,
          ).catchError((_) => null),
        ),
      );
    }
  }

  /// 清除指定漫画的缓存。
  void invalidate(String itemId) {
    final prefix = '$itemId:';
    final toRemove =
        _memoryCache.keys.where((key) => key.startsWith(prefix)).toList();
    for (final key in toRemove) {
      _currentBytes -= _memoryCache[key]?.length ?? 0;
      _memoryCache.remove(key);
    }
    _inFlight.removeWhere((key, _) => key.startsWith(prefix));
  }

  /// 清除所有缓存。
  void invalidateAll() {
    _memoryCache.clear();
    _inFlight.clear();
    _currentBytes = 0;
  }

  Future<Uint8List?> _fetchImage(String pageId) async {
    final image = await _api.getPageImage(pageId);
    return image.isEmpty ? null : image;
  }

  Uint8List? _takeCached(String key) {
    final bytes = _memoryCache.remove(key);
    if (bytes != null) {
      _memoryCache[key] = bytes;
    }
    return bytes;
  }

  void _putCache(String key, Uint8List bytes) {
    if (bytes.length > maxCacheBytes) {
      return;
    }

    final previous = _memoryCache.remove(key);
    if (previous != null) {
      _currentBytes -= previous.length;
    }

    while (_currentBytes + bytes.length > maxCacheBytes &&
        _memoryCache.isNotEmpty) {
      final oldest = _memoryCache.keys.first;
      final removed = _memoryCache.remove(oldest);
      if (removed != null) {
        _currentBytes -= removed.length;
      }
    }

    _memoryCache[key] = bytes;
    _currentBytes += bytes.length;
  }

  String _cacheKey(String itemId, String sourcePath, String? pageId) {
    return '$itemId:${pageId ?? sourcePath}';
  }
}
