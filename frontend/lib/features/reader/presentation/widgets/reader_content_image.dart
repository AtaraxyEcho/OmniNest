import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/reader/application/reader_image_provider.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_image_preview.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_pagination_engine.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';
import 'package:omninest/features/reader/reader_debug_log.dart';

/// 渲染阅读正文中的网络、data URI 或本地缓存图片。
class ReaderContentImage extends StatelessWidget {
  const ReaderContentImage({
    required this.block,
    required this.settings,
    required this.retryCount,
    required this.onRetry,
    this.itemId,
    this.onTap,
    super.key,
  });

  static const String _placeholderPrefix = '__IMG_';

  final ImageBlock block;
  final ReaderViewSettings settings;
  final int retryCount;
  final VoidCallback onRetry;
  final String? itemId;
  final ValueChanged<String>? onTap;

  @override
  Widget build(BuildContext context) {
    final isDataUri = block.src.startsWith('data:');
    final isCachedImage = block.src.startsWith(_placeholderPrefix);
    // 槽位在外层约束下计算：滚动 sliver 给无界高度（用完整槽位），
    // 有界上下文（翻页页框/测试视口）按可用高度钳制避免整块溢出。
    return LayoutBuilder(
      builder: (context, outerConstraints) {
        final width =
            outerConstraints.maxWidth.isFinite && outerConstraints.maxWidth > 0
                ? outerConstraints.maxWidth
                : MediaQuery.sizeOf(context).width;
        var slotHeight = ReaderPaginationEngine.imageSlotHeight(width);
        final available = outerConstraints.maxHeight;
        final hasCaption = block.caption?.isNotEmpty == true;
        if (available.isFinite && available > 0) {
          // 预留：上下内边距 48 + 容器边框 2 + 题注区（顶距 10 + 行高 + 余量）。
          final reserved = 54.0 + (hasCaption ? 32.0 : 0.0);
          final bounded = available - reserved;
          if (bounded > 0 && slotHeight > bounded) {
            slotHeight = bounded;
          }
        }
        return _buildContent(
          context,
          slotHeight: slotHeight,
          isDataUri: isDataUri,
          isCachedImage: isCachedImage,
        );
      },
    );
  }

  Widget _buildContent(
    BuildContext context, {
    required double slotHeight,
    required bool isDataUri,
    required bool isCachedImage,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Semantics(
        label: block.alt ?? block.caption ?? 'Image',
        child: Column(
          children: [
            GestureDetector(
              onTap: () {
                onTap?.call(block.src);
                ReaderImagePreview.show(
                  context,
                  block: block,
                  itemId: itemId,
                  retryCount: retryCount,
                );
              },
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: settings.onSurfaceVariantColor.withValues(
                      alpha: 0.10,
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    height: slotHeight,
                    width: double.infinity,
                    child:
                        isCachedImage
                            ? _buildCachedImage(slotHeight)
                            : isDataUri
                            ? _buildDataUriImage(slotHeight)
                            : Image.network(
                              retryCount > 0
                                  ? '${block.src}#retry=$retryCount'
                                  : block.src,
                              key: ValueKey('${block.src}#$retryCount'),
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.medium,
                              cacheWidth: 800,
                              loadingBuilder: (context, child, progress) {
                                if (progress == null) return child;
                                return _slotPlaceholder(
                                  slotHeight,
                                  CircularProgressIndicator(
                                    value:
                                        progress.expectedTotalBytes == null
                                            ? null
                                            : progress.cumulativeBytesLoaded /
                                                progress.expectedTotalBytes!,
                                  ),
                                );
                              },
                              errorBuilder:
                                  (_, _, _) => _buildError(slotHeight),
                            ),
                  ),
                ),
              ),
            ),
            if (block.caption != null && block.caption!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  block.caption!,
                  style: TextStyle(
                    color: settings.onSurfaceVariantColor,
                    fontSize: AppTypography.bodyMedium,
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 槽位内占位（加载中）：与最终图片同高，布局零漂移。
  Widget _slotPlaceholder(double slotHeight, Widget child) {
    return SizedBox(
      height: slotHeight,
      width: double.infinity,
      child: Center(child: child),
    );
  }

  Widget _buildCachedImage(double slotHeight) {
    if (itemId == null) return _buildError(slotHeight);
    final imagePath = block.src.substring(
      _placeholderPrefix.length,
      block.src.length - 2,
    );
    return _CachedReaderImage(
      itemId: itemId!,
      imagePath: imagePath,
      bust: retryCount,
      slotHeight: slotHeight,
      errorBuilder: () => _buildError(slotHeight),
    );
  }

  Widget _buildDataUriImage(double slotHeight) {
    try {
      final commaIndex = block.src.indexOf(',');
      if (commaIndex < 0) {
        if (kDebugMode) {
          readerDebugLog('ViewContent: invalid data URI — no comma found');
        }
        return _buildError(slotHeight);
      }
      final bytes = _dataUriDecodeCache.decode(
        block.src,
        () => base64Decode(block.src.substring(commaIndex + 1)),
      );
      if (kDebugMode) {
        readerDebugLog(
          'ViewContent: rendering data URI image — '
          '${bytes.length} bytes, mime=${block.src.substring(5, commaIndex)}',
        );
      }
      return Image.memory(
        bytes,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => _buildError(slotHeight),
      );
    } on Exception {
      return _buildError(slotHeight);
    }
  }

  Widget _buildError(double slotHeight) {
    return GestureDetector(
      onTap: onRetry,
      child: Container(
        height: slotHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: settings.onSurfaceVariantColor.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.broken_image_outlined,
              color: settings.onSurfaceVariantColor,
              size: 32,
            ),
            if (block.alt != null && block.alt!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  block.alt!,
                  style: TextStyle(
                    color: settings.onSurfaceVariantColor,
                    fontSize: AppTypography.bodySmall,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CachedReaderImage extends ConsumerWidget {
  const _CachedReaderImage({
    required this.itemId,
    required this.imagePath,
    required this.bust,
    required this.slotHeight,
    required this.errorBuilder,
  });

  final String itemId;
  final String imagePath;
  final int bust;
  final double slotHeight;
  final Widget Function() errorBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = ref.watch(
      readerCachedImageProvider((
        itemId: itemId,
        imagePath: imagePath,
        bust: bust,
      )),
    );
    return image.when(
      loading: () => _LoadingSlot(slotHeight: slotHeight),
      error: (_, _) => errorBuilder(),
      data: (bytes) {
        if (bytes == null || bytes.isEmpty) {
          return errorBuilder();
        }
        return Image.memory(
          bytes,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) => errorBuilder(),
        );
      },
    );
  }
}

/// 加载占位：与图片槽同高，解码前后布局零漂移。
class _LoadingSlot extends StatelessWidget {
  const _LoadingSlot({required this.slotHeight});

  final double slotHeight;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: slotHeight,
      width: double.infinity,
      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }
}

/// data URI 解码结果缓存。
///
/// 遗留缓存数据里的内嵌图片会在滚动重渲染时反复 build；按字节预算
/// 缓存解码结果，避免同一张大图每帧重新 base64 解码。
class _DataUriDecodeCache {
  static final _DataUriDecodeCache instance = _DataUriDecodeCache._();

  _DataUriDecodeCache._();

  static const _maxCacheBytes = 32 * 1024 * 1024;
  final LinkedHashMap<String, Uint8List> _entries = LinkedHashMap();

  Uint8List decode(String dataUri, Uint8List Function() decode) {
    final cached = _entries.remove(dataUri);
    if (cached != null) {
      // 重新插入尾部维持 LRU 顺序
      _entries[dataUri] = cached;
      return cached;
    }
    final bytes = decode();
    _entries[dataUri] = bytes;
    var totalBytes = _entries.values.fold<int>(0, (sum, v) => sum + v.length);
    while (totalBytes > _maxCacheBytes && _entries.isNotEmpty) {
      final oldest = _entries.keys.first;
      totalBytes -= _entries.remove(oldest)!.length;
    }
    return bytes;
  }
}

final _dataUriDecodeCache = _DataUriDecodeCache.instance;
