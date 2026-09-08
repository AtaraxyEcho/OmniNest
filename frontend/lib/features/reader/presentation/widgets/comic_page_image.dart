import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/reader/application/reader_comic_image_provider.dart';
import 'package:omninest/features/reader/domain/comic_models.dart';

/// 漫画图片在阅读器中的布局类型。
enum ComicPageImageLayout { paged, continuous }

/// 按需加载并展示单页漫画图片。
class ComicPageImage extends ConsumerStatefulWidget {
  const ComicPageImage({
    required this.page,
    required this.itemId,
    required this.surfaceColor,
    required this.layout,
    this.onLayout,
    super.key,
  });

  final ComicPage page;
  final String itemId;
  final Color surfaceColor;
  final ComicPageImageLayout layout;

  /// 页面布局完成回调，参数依次为页码索引和渲染高度。
  final void Function(int index, double height)? onLayout;

  @override
  ConsumerState<ComicPageImage> createState() => _ComicPageImageState();
}

class _ComicPageImageState extends ConsumerState<ComicPageImage> {
  Uint8List? _imageBytes;
  bool _loading = false;
  String? _error;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(ComicPageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page.id != widget.page.id ||
        oldWidget.page.sourcePath != widget.page.sourcePath ||
        oldWidget.itemId != widget.itemId) {
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
      _imageBytes = null;
    });

    try {
      final loader = ref.read(comicImageLoaderProvider);
      final bytes = await loader.getImage(
        widget.itemId,
        widget.page.sourcePath,
        pageId: widget.page.id,
      );
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _imageBytes = bytes;
          _loading = false;
        });
        _reportLayout();
      }
    } catch (error) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _error = error.toString();
          _loading = false;
        });
      }
    }
  }

  void _reportLayout() {
    if (widget.onLayout == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final size = context.size;
      if (size != null && size.height > 0) {
        widget.onLayout!(widget.page.pageIndex, size.height);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final logicalWidth =
            constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : MediaQuery.sizeOf(context).width;
        final cacheWidth =
            (logicalWidth * MediaQuery.devicePixelRatioOf(context))
                .round()
                .clamp(1, 2560)
                .toInt();
        final content = _buildContent(cacheWidth);
        if (widget.layout == ComicPageImageLayout.paged) {
          return SizedBox.expand(child: content);
        }
        return AspectRatio(aspectRatio: _pageAspectRatio, child: content);
      },
    );
  }

  double get _pageAspectRatio {
    final width = widget.page.width;
    final height = widget.page.height;
    if (width != null && height != null && width > 0 && height > 0) {
      return width / height;
    }
    return 3 / 4;
  }

  Widget _buildContent(int cacheWidth) {
    if (_loading) {
      return ColoredBox(
        color: widget.surfaceColor,
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_error != null || _imageBytes == null) {
      return _ImageFailure(
        surfaceColor: widget.surfaceColor,
        message: AppLocalizations.of(context).readerComicImageLoadFailed,
        onRetry: _loadImage,
      );
    }
    return Image.memory(
      _imageBytes!,
      fit: BoxFit.contain,
      width: double.infinity,
      height: double.infinity,
      cacheWidth: cacheWidth,
      gaplessPlayback: true,
      errorBuilder:
          (context, error, stackTrace) => _ImageFailure(
            surfaceColor: widget.surfaceColor,
            message: AppLocalizations.of(context).readerComicImageDecodeFailed,
          ),
    );
  }
}

class _ImageFailure extends StatelessWidget {
  const _ImageFailure({
    required this.surfaceColor,
    required this.message,
    this.onRetry,
  });

  final Color surfaceColor;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: surfaceColor,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.broken_image_outlined,
              size: 42,
              color: Colors.grey[600],
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: AppTypography.bodyMedium,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 8),
              IconButton(
                tooltip: AppLocalizations.of(context).readerRetry,
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                color: Colors.white70,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
