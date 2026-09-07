import 'dart:async';

import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:omninest/features/photos/domain/photo.dart';

/// 幻灯片专用解码位图缓存。
///
/// 所有权模型：位图本体由 Flutter ImageCache 持有（解码后保留 stream 监听，
/// 使位图处于 live 状态不被驱逐），本缓存只维护 current ± [radius] 的窗口引用，
/// 窗口外仅移除引用（不 dispose——位图归 ImageCache 所有）。
/// - single-flight：同一张图并发请求只做一次解码；
/// - obtain 带超时兜底：解码挂起/失败归一为 null，由页面进入 failed 可重试态。
class SlideshowImageCache {
  SlideshowImageCache({this.radius = 1});

  /// 解码窗口半径（保留 current ± radius）。
  final int radius;

  /// 单张解码兜底超时：超时进入 failed（页面提供重试），避免无限 spinner。
  static const _obtainTimeout = Duration(seconds: 15);

  final Map<String, ui.Image> _decoded = {};
  final Map<String, Future<ui.Image?>> _loading = {};
  final Set<String> _window = {};
  bool _disposed = false;

  /// 读取已解码位图（未解码返回 null）。
  ui.Image? peek(String id) => _decoded[id];

  /// 更新缓存窗口：窗口外仅移除引用（位图归 ImageCache 所有，不 dispose）。
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
    _decoded.removeWhere((id, _) => !_window.contains(id));
  }

  /// Single-flight 获取解码位图。
  ///
  /// 解码完成后：窗口内的图登记到窗口引用；窗口外（解码期间已切走并更新
  /// 窗口）不登记。任何失败/超时都归一为 null，绝不抛出。
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
    final memCacheWidth = (screenSize.width * dpr).round().clamp(1, 8192);
    final provider = ResizeImage.resizeIfNeeded(
      memCacheWidth,
      null,
      CachedNetworkImageProvider(
        url,
        cacheKey:
            item.sourceUrl != null ? item.sourceCacheKey : item.coverCacheKey,
      ),
    );
    final future = _decodeViaResolve(provider, context).timeout(_obtainTimeout);
    _loading[id] = future;
    return future.then((image) {
      // 窗口竞态防护：解码期间可能已切走并更新窗口，窗口外的图不登记；
      // 切换调用方拿到位图后会显式 retain。
      if (image != null && !_disposed && _window.contains(id)) {
        _decoded[id] = image;
      }
      return image;
    });
  }

  /// 通过 ImageCache 解码并保留 stream 监听（live 保活，位图不被驱逐）。
  Future<ui.Image?> _decodeViaResolve(
    ImageProvider<Object> provider,
    BuildContext context,
  ) {
    final completer = Completer<ui.Image?>();
    late final ImageStreamListener listener;
    final stream = provider.resolve(createLocalImageConfiguration(context));
    listener = ImageStreamListener(
      (ImageInfo info, bool synchronousCall) {
        // 保留监听：持有活跃监听使 ImageCache 将位图视为 live、免于驱逐。
        if (!completer.isCompleted) completer.complete(info.image);
      },
      onError: (Object error, StackTrace? stackTrace) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.complete(null);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }

  /// 强制写入缓存（切换目标：切换后必在窗口内，供交叉动画与回看使用）。
  void retain(String id, ui.Image image) {
    if (_disposed) return;
    _decoded[id] = image;
  }

  /// 清空窗口引用。位图本体归 ImageCache 所有（live 保活），此处不 dispose。
  void dispose() {
    _disposed = true;
    _decoded.clear();
    _loading.clear();
    _window.clear();
  }
}
