import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'package:omninest/features/photos/domain/photo.dart';

/// 幻灯片专用解码位图缓存：完全绕过 Flutter ImageCache，独占位图生命周期。
///
/// - 下载复用 DefaultCacheManager 的磁盘缓存（与 CachedNetworkImage 共享，不重复下载）；
/// - 解码通过 ImmutableBuffer + ImageDescriptor 自主完成，产生的 [ui.Image]
///   从未进入 ImageCache，因此归本缓存独占，[dispose] / [pruneWindow] 可安全释放；
/// - single-flight：同一张图并发请求只做一次下载+解码；
/// - 窗口化：只保留 current ± [radius] 的位图，窗口外显式 dispose 释放 native 内存。
class SlideshowImageCache {
  SlideshowImageCache({this.radius = 1, this.maxDecodeWidth = 4096});

  /// 解码窗口半径（保留 current ± radius）。
  final int radius;

  /// 单张解码宽度上限：viewport 分辨率足够幻灯片 contain 显示，
  /// 超大原图不做全尺寸解码（需要放大查看时再走详情页分级加载）。
  final int maxDecodeWidth;

  final Map<String, ui.Image> _decoded = {};
  final Map<String, Future<ui.Image?>> _loading = {};
  final Set<String> _window = {};
  bool _disposed = false;

  /// 读取已解码位图（未解码返回 null）。
  ui.Image? peek(String id) => _decoded[id];

  /// 更新缓存窗口并释放窗口外位图。调用时机固定在动画完成后，
  /// 窗口外位图必然不在显示中，dispose 无呈现风险。
  void updateWindow(List<PhotoItem> photos, int current) {
    if (_disposed || photos.isEmpty) return;
    _window
      ..clear()
      ..addAll({
        for (var offset = -radius; offset <= radius; offset++)
          photos[((current + offset) % photos.length + photos.length) %
                  photos.length]
              .id,
      });
    final evicted = <ui.Image>[];
    _decoded.removeWhere((id, image) {
      if (_window.contains(id)) return false;
      evicted.add(image);
      return true;
    });
    for (final image in evicted) {
      image.dispose();
    }
  }

  /// Single-flight 获取解码位图。
  ///
  /// 解码完成后：窗口内的图写入缓存；窗口外（解码期间已切走并 prune）不写回，
  /// 由调用方决定是否 retain。任何失败都归一为 null，绝不抛出。
  Future<ui.Image?> obtain(PhotoItem item, BuildContext context) async {
    if (_disposed) return null;
    final id = item.id;
    final cached = _decoded[id];
    if (cached != null) return cached;
    final loading = _loading[id];
    if (loading != null) return loading;
    final url = item.sourceUrl ?? item.coverUrl;
    if (url == null || url.isEmpty) return null;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final screenSize = MediaQuery.sizeOf(context);
    final targetWidth = (screenSize.width * dpr).round().clamp(
      1,
      maxDecodeWidth,
    );
    final future = _decodeFromNetwork(url, targetWidth)
        .then((image) {
          // 窗口竞态防护：解码期间可能已切走并 prune，窗口外的图不写回；
          // 切换调用方拿到位图后会显式 retain。
          if (image != null && !_disposed && _window.contains(id)) {
            _decoded[id] = image;
          }
          return image;
        })
        .whenComplete(() => _loading.remove(id));
    _loading[id] = future;
    return future;
  }

  /// 强制写入缓存（切换目标：切换后必在窗口内，供交叉动画与回看使用）。
  void retain(String id, ui.Image image) {
    if (_disposed) return;
    _decoded[id] = image;
  }

  /// 释放全部位图。页面销毁后到达的解码结果不再写回，位图交由 GC 回收。
  void dispose() {
    _disposed = true;
    for (final image in _decoded.values) {
      image.dispose();
    }
    _decoded.clear();
    _loading.clear();
  }

  /// 下载（复用磁盘缓存）并自主解码为 ui.Image——完全不经过 ImageCache。
  Future<ui.Image?> _decodeFromNetwork(String url, int targetWidth) async {
    try {
      final file = await DefaultCacheManager().getSingleFile(url);
      final buffer = await ui.ImmutableBuffer.fromFilePath(file.path);
      ui.ImageDescriptor? descriptor;
      ui.Codec? codec;
      try {
        descriptor = await ui.ImageDescriptor.encoded(buffer);
        final width = descriptor.width <= 0 ? targetWidth : descriptor.width;
        final height = descriptor.height <= 0 ? 1 : descriptor.height;
        // 按比例缩到目标宽度（不超过解码上限）；小图保持原尺寸。
        var codecWidth = targetWidth;
        var codecHeight = (height * targetWidth / width).round();
        if (width <= targetWidth) {
          codecWidth = width;
          codecHeight = height;
        }
        codec = await descriptor.instantiateCodec(
          targetWidth: codecWidth,
          targetHeight: codecHeight,
        );
        final frame = await codec.getNextFrame();
        return frame.image;
      } finally {
        codec?.dispose();
        descriptor?.dispose();
        buffer.dispose();
      }
    } catch (error, stackTrace) {
      debugPrint('SlideshowImageCache decode failed [$url]: $error');
      debugPrintStack(stackTrace: stackTrace, maxFrames: 12);
      return null;
    }
  }
}
