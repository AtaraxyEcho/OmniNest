import 'package:flutter/material.dart';
import 'package:omninest/features/reader/presentation/widgets/block_clipper.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_image.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 判断章节是否属于封面/书讯型短章（仅用于开书跳过判定）。
///
/// 启发式：正文极少，或几乎只有图片/标题。只允许
/// ReaderViewPageMixin._maybeSkipCoverChapter 使用；
/// 页面渲染必须改用 [isDedicatedCoverPage] 的严格结构判定，
/// 否则普通短章会被误判为封面并绕过 PageSlice 双重渲染图片。
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

/// 判断章节是否具备"独立封面页"的严格结构（仅用于页面渲染判定）。
///
/// 仅接受：仅图片 / 仅图片 + 至多一个短标题或图注块。任何含正文的
/// 图文混排章节（如 `段落 + 图片 + 段落`）都必须走 PageSlice 分页，
/// 保证每个 ImageBlock 只属于一个页面。
bool isDedicatedCoverPage({required List<ContentBlock> blocks}) {
  if (blocks.isEmpty) {
    return false;
  }
  final nonImageBlocks = blocks.where((b) => b is! ImageBlock).toList();
  if (nonImageBlocks.length > 1) {
    return false;
  }
  if (nonImageBlocks.isEmpty) {
    return true;
  }
  final only = nonImageBlocks.single;
  final isTitleLike =
      only is HeadingBlock ||
      (only is ParagraphBlock && only.lines.length <= 2);
  return isTitleLike && BlockClipper.blockCharCount(only) <= 60;
}

/// 翻页模式的封面/书讯页：居中标题 + 可选图片，对齐主流 title page。
///
/// [visibleBlocks] 只能来自当前 PageSlice 的裁剪结果——封面页不得
/// 从整章 blocks 拿内容，否则与图片独占页双重渲染同一图片。
class ReaderCoverPage extends StatelessWidget {
  const ReaderCoverPage({
    required this.title,
    required this.settings,
    required this.visibleBlocks,
    this.itemId,
    super.key,
  });

  final String title;
  final ReaderViewSettings settings;
  final List<ContentBlock> visibleBlocks;
  final String? itemId;

  @override
  Widget build(BuildContext context) {
    final images = visibleBlocks
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
