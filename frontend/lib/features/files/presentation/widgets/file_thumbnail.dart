import 'package:cached_network_image/cached_network_image.dart';
import 'package:omninest/app/theme/feature/files_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/features/files/application/file_download_url_provider.dart';
import 'package:omninest/features/files/domain/file_node.dart';

/// 文件缩略图组件。
/// 图片文件显示实际缩略图，其他文件显示类型图标。
class FileThumbnail extends ConsumerStatefulWidget {
  const FileThumbnail({
    required this.file,
    this.size = 40,
    this.borderRadius,
    this.zoomOnHover = false,
    super.key,
  });

  final FileNode file;
  final double size;

  /// 图片圆角；为空时沿用历史 8px 圆角，工位皮肤传 [BorderRadius.zero]。
  final BorderRadius? borderRadius;

  /// 悬停时图片内容放大（Photos 照片卡同构的裁切缩放，卡片视图启用）：
  /// 缩略图外框钉死，放大只作用于图片内部；图标类条目不受影响。
  final bool zoomOnHover;

  @override
  ConsumerState<FileThumbnail> createState() => _FileThumbnailState();
}

class _FileThumbnailState extends ConsumerState<FileThumbnail> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final file = widget.file;
    final size = widget.size;
    // 三级降级：媒体库封面（音乐/影视/阅读）→ 图片自身内容 → 类型图标。
    final coverFileId = file.coverFileId;
    if (!file.isFolder && coverFileId != null && coverFileId.isNotEmpty) {
      final coverUrl =
          ref.watch(fileDownloadUrlProvider(coverFileId)).asData?.value;
      if (coverUrl != null && coverUrl.isNotEmpty) {
        return ClipRRect(
          borderRadius: widget.borderRadius ?? BorderRadius.zero,
          child: CachedNetworkImage(
            imageUrl: coverUrl,
            width: size,
            height: size,
            fit: BoxFit.cover,
            memCacheWidth: (size * 2).toInt(),
            placeholder: (context, url) => _FileIcon(file: file, size: size),
            errorWidget:
                (context, url, error) => _FileIcon(file: file, size: size),
          ),
        );
      }
      return _FileIcon(file: file, size: size);
    }
    if (file.isFolder || !_isImageMimeType(file.mimeType)) {
      return _FileIcon(file: file, size: size);
    }

    final urlAsync = ref.watch(fileDownloadUrlProvider(file.id));
    return urlAsync.when(
      data: (url) {
        if (url == null || url.isEmpty) {
          return _FileIcon(file: file, size: size);
        }
        Widget image = ClipRRect(
          // 工位皮肤统一直角；需要圆角的旧场景经 borderRadius 显式传入。
          borderRadius: widget.borderRadius ?? BorderRadius.zero,
          child: AnimatedScale(
            // 内容裁切缩放：卡片视图悬停时放大图片内部像素。
            scale:
                widget.zoomOnHover &&
                        _hovered &&
                        !MediaQuery.disableAnimationsOf(context)
                    ? 1.04
                    : 1.0,
            duration: MotionToken.normal,
            curve: MotionToken.curve,
            child: CachedNetworkImage(
              imageUrl: url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              memCacheWidth: (size * 2).toInt(),
              placeholder: (context, url) => _FileIcon(file: file, size: size),
              errorWidget:
                  (context, url, error) => _FileIcon(file: file, size: size),
            ),
          ),
        );
        if (!widget.zoomOnHover) {
          return image;
        }
        return MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: image,
        );
      },
      loading: () => _FileIcon(file: file, size: size),
      error: (e, st) => _FileIcon(file: file, size: size),
    );
  }

  static bool _isImageMimeType(String? mimeType) {
    if (mimeType == null) return false;
    return mimeType.startsWith('image/');
  }
}

/// 通用文件类型图标。
class _FileIcon extends StatelessWidget {
  const _FileIcon({required this.file, required this.size});

  final FileNode file;
  final double size;

  @override
  Widget build(BuildContext context) {
    final accent =
        file.isFolder
            ? context.filesColors.tertiary
            : context.filesColors.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size > 48 ? 14 : 12),
      ),
      child: Icon(
        file.isFolder ? Icons.folder_rounded : _fileTypeIcon(file.mimeType),
        size: size * 0.5,
        color: accent,
      ),
    );
  }

  static IconData _fileTypeIcon(String? mimeType) {
    if (mimeType == null) return Icons.insert_drive_file_outlined;
    if (mimeType.startsWith('video/')) return Icons.movie_outlined;
    if (mimeType.startsWith('audio/')) return Icons.audio_file_outlined;
    if (mimeType.startsWith('image/')) return Icons.image_outlined;
    if (mimeType == 'application/pdf') return Icons.picture_as_pdf_outlined;
    if (mimeType.startsWith('text/')) return Icons.description_outlined;
    return Icons.insert_drive_file_outlined;
  }
}
