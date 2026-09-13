import 'package:flutter/material.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_image.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 判断章节是否属于封面/书讯型短章。
///
/// 启发式：正文极少，或几乎只有图片/标题。用于翻页模式的独立封面页布局，
/// 以及开书时跳过封面（见 ReaderViewPageMixin._maybeSkipCoverChapter）。
bool isCoverLikeChapter({
  required int totalChars,
  required List<ContentBlock> blocks,
}) {
  if (totalChars <= 0) {
    return blocks.any((b) => b is ImageBlock);
  }
  if (totalChars <= 120) {
    return true;
  }
  if (blocks.isEmpty) {
    return false;
  }
  final imageCount = blocks.whereType<ImageBlock>().length;
  return imageCount > 0 &&
      totalChars <= 400 &&
      imageCount >= blocks.length ~/ 2;
}

/// 翻页模式的封面/书讯页：居中标题 + 可选图片，对齐主流 title page。
class ReaderCoverPage extends StatelessWidget {
  const ReaderCoverPage({
    required this.title,
    required this.settings,
    required this.blocks,
    this.itemId,
    super.key,
  });

  final String title;
  final ReaderViewSettings settings;
  final List<ContentBlock> blocks;
  final String? itemId;

  @override
  Widget build(BuildContext context) {
    final images = blocks
        .whereType<ImageBlock>()
        .take(2)
        .toList(growable: false);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final image in images) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: ReaderContentImage(
                    block: image,
                    settings: settings,
                    retryCount: 0,
                    onRetry: () {},
                    itemId: itemId,
                  ),
                ),
                const SizedBox(height: 28),
              ],
              if (title.trim().isNotEmpty)
                Text(
                  title.trim(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: settings.onSurfaceColor,
                    fontSize: (settings.fontSize * 1.45).clamp(22, 36),
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
