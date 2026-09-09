import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/reader/application/reader_image_provider.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';

/// 正文图片全屏预览：暗底、可缩放平移、点空白或关闭按钮退出。
class ReaderImagePreview extends ConsumerStatefulWidget {
  const ReaderImagePreview({
    required this.block,
    required this.retryCount,
    this.itemId,
    super.key,
  });

  final ImageBlock block;
  final String? itemId;
  final int retryCount;

  static Future<void> show(
    BuildContext context, {
    required ImageBlock block,
    String? itemId,
    int retryCount = 0,
  }) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        barrierDismissible: true,
        pageBuilder: (_, animation, _) {
          return FadeTransition(
            opacity: animation,
            child: ReaderImagePreview(
              block: block,
              itemId: itemId,
              retryCount: retryCount,
            ),
          );
        },
      ),
    );
  }

  @override
  ConsumerState<ReaderImagePreview> createState() => _ReaderImagePreviewState();
}

class _ReaderImagePreviewState extends ConsumerState<ReaderImagePreview> {
  static const _placeholderPrefix = '__IMG_';

  @override
  Widget build(BuildContext context) {
    final block = widget.block;
    final caption = block.caption;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).maybePop(),
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.94)),
            ),
          ),
          Positioned.fill(
            child: SafeArea(
              child: InteractiveViewer(
                maxScale: 4,
                minScale: 1,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 56,
                    ),
                    child: _buildImage(),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: SafeArea(
              child: IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black.withValues(alpha: 0.35),
                ),
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              ),
            ),
          ),
          if (caption != null && caption.isNotEmpty)
            Positioned(
              left: 16,
              right: 16,
              bottom: 20,
              child: SafeArea(
                child: Text(
                  caption,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImage() {
    final block = widget.block;
    final isDataUri = block.src.startsWith('data:');
    final isCachedImage = block.src.startsWith(_placeholderPrefix);
    if (isCachedImage && widget.itemId != null) {
      final imagePath = block.src.substring(
        _placeholderPrefix.length,
        block.src.length - 2,
      );
      return ref
          .watch(
            readerCachedImageProvider((
              itemId: widget.itemId!,
              imagePath: imagePath,
              bust: widget.retryCount,
            )),
          )
          .when(
            loading:
                () => const SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white54,
                  ),
                ),
            error: (_, _) => _errorIcon(),
            data: (bytes) {
              if (bytes == null || bytes.isEmpty) {
                return _errorIcon();
              }
              return Image.memory(
                bytes,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => _errorIcon(),
              );
            },
          );
    }
    if (isDataUri) {
      try {
        final commaIndex = block.src.indexOf(',');
        if (commaIndex < 0) {
          return _errorIcon();
        }
        final bytes = base64Decode(block.src.substring(commaIndex + 1));
        return Image.memory(
          bytes,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _errorIcon(),
        );
      } on Exception {
        return _errorIcon();
      }
    }
    return Image.network(
      block.src,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      loadingBuilder: (context, child, progress) {
        if (progress == null) {
          return child;
        }
        return const SizedBox(
          width: 48,
          height: 48,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white54,
          ),
        );
      },
      errorBuilder: (_, _, _) => _errorIcon(),
    );
  }

  Widget _errorIcon() {
    return const Icon(
      Icons.broken_image_outlined,
      color: Colors.white38,
      size: 48,
    );
  }
}
