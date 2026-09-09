import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/reader/application/reader_image_provider.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Semantics(
        label: block.alt ?? block.caption ?? 'Image',
        child: Column(
          children: [
            GestureDetector(
              onTap: () => onTap?.call(block.src),
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
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final maxImageHeight = _maxImageHeight(
                        context,
                        constraints.maxWidth.isFinite
                            ? constraints.maxWidth
                            : MediaQuery.sizeOf(context).width,
                      );
                      return ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: maxImageHeight),
                        child:
                            isCachedImage
                                ? _buildCachedImage()
                                : isDataUri
                                ? _buildDataUriImage()
                                : Image.network(
                                  retryCount > 0
                                      ? '${block.src}#retry=$retryCount'
                                      : block.src,
                                  key: ValueKey('${block.src}#$retryCount'),
                                  width: double.infinity,
                                  fit: BoxFit.fitWidth,
                                  filterQuality: FilterQuality.medium,
                                  cacheWidth: 800,
                                  loadingBuilder: (context, child, progress) {
                                    if (progress == null) return child;
                                    return SizedBox(
                                      height: 120,
                                      child: Center(
                                        child: CircularProgressIndicator(
                                          value:
                                              progress.expectedTotalBytes ==
                                                      null
                                                  ? null
                                                  : progress
                                                          .cumulativeBytesLoaded /
                                                      progress
                                                          .expectedTotalBytes!,
                                        ),
                                      ),
                                    );
                                  },
                                  errorBuilder: (_, _, _) => _buildError(),
                                ),
                      );
                    },
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

  /// 限制超高图：避免 SliverList 中整块长图被一次滑动“翻过”。
  double _maxImageHeight(BuildContext context, double width) {
    final viewportHeight = MediaQuery.sizeOf(context).height;
    return math.min(width * 1.35, viewportHeight * 0.78);
  }

  Widget _buildCachedImage() {
    if (itemId == null) return _buildError();
    final imagePath = block.src.substring(
      _placeholderPrefix.length,
      block.src.length - 2,
    );
    return _CachedReaderImage(
      itemId: itemId!,
      imagePath: imagePath,
      bust: retryCount,
      errorBuilder: _buildError,
    );
  }

  Widget _buildDataUriImage() {
    try {
      final commaIndex = block.src.indexOf(',');
      if (commaIndex < 0) {
        if (kDebugMode) {
          readerDebugLog('ViewContent: invalid data URI — no comma found');
        }
        return _buildError();
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
        width: double.infinity,
        fit: BoxFit.fitWidth,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => _buildError(),
      );
    } on Exception {
      return _buildError();
    }
  }

  Widget _buildError() {
    return GestureDetector(
      onTap: onRetry,
      child: Container(
        height: 120,
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
    required this.errorBuilder,
  });

  final String itemId;
  final String imagePath;
  final int bust;
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
      loading:
          () => const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
      error: (_, _) => errorBuilder(),
      data: (bytes) {
        if (bytes == null || bytes.isEmpty) {
          return errorBuilder();
        }
        return Image.memory(
          bytes,
          width: double.infinity,
          fit: BoxFit.fitWidth,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) => errorBuilder(),
        );
      },
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
      _entries[dataUri] = cached; // 重新插入尾部维持 LRU 顺序
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
