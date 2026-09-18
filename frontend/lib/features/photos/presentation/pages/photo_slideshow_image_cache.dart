import 'dart:async';

import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:omninest/features/photos/domain/photo.dart';

/// 幻灯片图片质量档位。
///
/// - [thumbnail]：coverUrl 按 400px 解码（网格/快速切换，秒开）；
/// - [preview]：sourceUrl 按屏宽降采样解码（全屏真高清渐进替换）。
enum ImageQuality { thumbnail, preview }

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

  /// 显示器物理像素宽;窗口 maximize/全屏不改变该值。
  static double? _displayPhysicalWidth() {
    final views = ui.PlatformDispatcher.instance.views;
    if (views.isEmpty) {
      return null;
    }
    final width = views.first.display.size.width;
    return width.isFinite && width > 0 ? width : null;
  }

  /// preview 档解码宽:绑定显示器物理像素而非窗口尺寸——全屏切换/窗口缩放
  /// 不更换解码键,且可在进入全屏吸附前预解码出最终档位,首屏不再等
  /// "窗口宽→全屏宽"的二次解码。上限 4096 覆盖 4K 全宽且不超常规纹理上限。
  @visibleForTesting
  static int previewDecodeWidthFor({
    required double dpr,
    required double fallbackWidth,
  }) {
    final displayWidth = _displayPhysicalWidth() ?? fallbackWidth;
    return (displayWidth * dpr).round().clamp(1, 4096);
  }

  /// 单张解码兜底超时：超时进入 failed（页面提供重试），避免无限 spinner。
  static const _obtainTimeout = Duration(seconds: 15);

  final Map<String, ui.Image> _decoded = {};
  final Map<String, Future<ui.Image?>> _loading = {};
  final Set<String> _window = {};
  bool _disposed = false;

  /// 统一解码缓存键：照片 id + 质量档位；读、写、窗口清理必须使用同一键形。
  static String keyFor(String photoId, ImageQuality quality) =>
      '$photoId-${quality.name}';

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
    // 缓存键带质量档位，清理按“窗口内 id + 全部档位”的组合键匹配，
    // 不能用裸照片 id 过滤，否则会误删全部带档位后缀的解码结果。
    final validKeys = <String>{
      for (final id in _window) ...[
        keyFor(id, ImageQuality.thumbnail),
        keyFor(id, ImageQuality.preview),
      ],
    };
    _decoded.removeWhere((key, _) => !validKeys.contains(key));
  }

  /// Single-flight 获取解码位图。
  ///
  /// 解码完成后：窗口内的图登记到窗口引用；窗口外（解码期间已切走并更新
  /// 窗口）不登记。任何失败/超时都归一为 null，绝不抛出。
  ///
  /// 档位：thumbnail=coverUrl@400（快速切换秒显）；
  /// preview=sourceUrl 原图按屏宽降采样解码（真高清渐进替换）。
  Future<ui.Image?> obtain(
    PhotoItem item,
    ImageQuality quality,
    BuildContext context,
  ) async {
    if (_disposed) return null;
    final id = item.id;
    final key = keyFor(id, quality);
    final cached = _decoded[key];
    if (cached != null) return cached;
    final loading = _loading[key];
    if (loading != null) return loading;
    // thumbnail 档用 cover（1024 WebP 秒开）；preview 档用原图（真高清）。
    final url =
        quality == ImageQuality.thumbnail ? item.coverUrl : item.sourceUrl;
    if (url == null || url.isEmpty) return null;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final memCacheWidth = switch (quality) {
      ImageQuality.thumbnail => 400,
      ImageQuality.preview => previewDecodeWidthFor(
        dpr: dpr,
        fallbackWidth: MediaQuery.sizeOf(context).width,
      ),
    };
    final cacheKey =
        quality == ImageQuality.thumbnail
            ? item.coverCacheKey
            : item.sourceCacheKey;
    final provider = ResizeImage.resizeIfNeeded(
      memCacheWidth,
      null,
      CachedNetworkImageProvider(url, cacheKey: cacheKey),
    );
    final future = _decodeViaResolve(provider, context).timeout(_obtainTimeout);
    _loading[key] = future;
    return future.then<ui.Image?>(
      (image) {
        if (identical(_loading[key], future)) {
          _loading.remove(key);
        }
        // 窗口竞态防护：解码期间可能已切走并更新窗口，窗口外的图不登记；
        // 切换调用方拿到位图后会显式 retain。
        if (image != null && !_disposed && _window.contains(id)) {
          _decoded[key] = image;
        }
        return image;
      },
      onError: (Object error) {
        // 超时/解码异常归一为 null 并清理 single-flight 表，
        // 避免失败的 Future 永久占据键位导致该照片后续无法重试。
        if (identical(_loading[key], future)) {
          _loading.remove(key);
        }
        return null;
      },
    );
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

  /// 强制写入缓存（切换目标 / 渐进升级：写入后必在窗口内，供交叉动画与回看使用）。
  /// [key] 必须是 [keyFor] 生成的完整键；写入裸照片 id 会与读取键形错位，
  /// 位图永远不会被 obtain 命中。
  void retain(String key, ui.Image image) {
    if (_disposed) return;
    _decoded[key] = image;
  }

  /// 清空窗口引用。位图本体归 ImageCache 所有（live 保活），此处不 dispose。
  void dispose() {
    _disposed = true;
    _decoded.clear();
    _loading.clear();
    _window.clear();
  }
}
