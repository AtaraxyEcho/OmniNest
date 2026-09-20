import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/data/reader_image_cache.dart';
import 'package:omninest/features/reader/reader_debug_log.dart';

/// 阅读封面字节的进程内 LRU 缓存。
///
/// 封面字节经认证接口拉取，浏览器无法按 URL 复用；autoDispose provider
/// 随组件卸载销毁状态后重挂会重复请求。此缓存以 itemId 为键跨卸载存活，
/// 容量按封面体积（约 10-200KB）取 64 条封顶。
class ReaderCoverByteCache {
  static const int _maxEntries = 64;
  static final LinkedHashMap<String, Uint8List> _entries =
      LinkedHashMap<String, Uint8List>();

  static Uint8List? read(String itemId) {
    final bytes = _entries.remove(itemId);
    if (bytes != null) {
      _entries[itemId] = bytes;
    }
    return bytes;
  }

  static void write(String itemId, Uint8List bytes) {
    _entries.remove(itemId);
    _entries[itemId] = bytes;
    while (_entries.length > _maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  static void remove(String itemId) {
    _entries.remove(itemId);
  }
}

/// 阅读封面图片字节。
///
/// 命中 [ReaderCoverByteCache] 时直接返回，不重复发起认证请求；
/// 未命中才走接口下载并回填缓存。
final coverBytesProvider = FutureProvider.autoDispose
    .family<Uint8List?, String>((ref, itemId) async {
      final cached = ReaderCoverByteCache.read(itemId);
      if (cached != null && cached.isNotEmpty) {
        return cached;
      }
      try {
        final bytes = await ref.read(readerApiProvider).getCoverImage(itemId);
        if (bytes != null && bytes.isNotEmpty) {
          ReaderCoverByteCache.write(itemId, bytes);
        }
        return bytes;
      } on Exception catch (error) {
        if (kDebugMode) {
          readerDebugLog('CoverImage: download failed for $itemId: $error');
        }
        return null;
      }
    });

/// 阅读正文缓存图片字节。
///
/// [request.bust] 为失败重试计数：占位图点击重试时递增，family 键
/// 随之变化使 provider 重新执行，而不是永远缓存上一次的失败结果。
final readerCachedImageProvider = FutureProvider.autoDispose
    .family<Uint8List?, ({String itemId, String imagePath, int bust})>((
      ref,
      request,
    ) {
      return ReaderImageCache.loadImage(
        itemId: request.itemId,
        imagePath: request.imagePath,
      );
    });
