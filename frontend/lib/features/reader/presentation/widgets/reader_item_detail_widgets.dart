import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/reader_colors.dart';
import 'package:omninest/features/reader/application/reader_progress_snapshot.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/reader_l10n_helpers.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_cover_image.dart';

/// 书籍详情页根据视口宽度解析出的布局约束。
@immutable
class ReaderDetailLayout {
  const ReaderDetailLayout({
    required this.isDesktop,
    required this.maxContentWidth,
    required this.horizontalPadding,
    required this.directoryMaxHeight,
    required this.previewChapterCount,
    required this.coverWidth,
    required this.coverHeight,
    required this.summaryGap,
    required this.sectionGap,
  });

  final bool isDesktop;
  final double maxContentWidth;
  final double horizontalPadding;
  final double directoryMaxHeight;
  final int previewChapterCount;
  final double coverWidth;
  final double coverHeight;
  final double summaryGap;
  final double sectionGap;

  /// 根据当前可用宽度生成稳定的单列或双列布局。
  factory ReaderDetailLayout.resolve(double width) {
    final isDesktop = width >= 900;
    return ReaderDetailLayout(
      isDesktop: isDesktop,
      maxContentWidth: width >= 1800 ? 1280 : 1080,
      horizontalPadding:
          width >= 1800
              ? 48
              : width >= 1200
              ? 36
              : width >= 600
              ? 24
              : 16,
      directoryMaxHeight: isDesktop ? 560 : 420,
      previewChapterCount: isDesktop ? 10 : 6,
      coverWidth: isDesktop ? 216 : 164,
      coverHeight: isDesktop ? 307 : 233,
      summaryGap: isDesktop ? 44 : 24,
      sectionGap: isDesktop ? 36 : 28,
    );
  }
}

/// 标题/简介区域的胶囊数据
class CapsuleData {
  const CapsuleData(this.label, this.color);
  final String label;
  final Color color;
}

/// 详情页封面组件
class DetailCover extends ConsumerWidget {
  const DetailCover({
    required this.item,
    this.width = 200,
    this.height = 284,
    super.key,
  });

  final ReaderItem item;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: width,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: context.readerColors.surfaceContainerHighest,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child:
          item.hasCover
              ? AuthCoverImage(
                itemId: item.id,
                fit: BoxFit.cover,
                fallback: CoverFallback(item: item),
              )
              : CoverFallback(item: item),
    );
  }
}

/// 封面加载失败时的回退组件
class CoverFallback extends StatelessWidget {
  const CoverFallback({required this.item, super.key});

  final ReaderItem item;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            context.readerColors.coverGradientStart,
            context.readerColors.coverGradientEnd,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              item.title.trim().isEmpty
                  ? 'R'
                  : item.title.trim().substring(0, 1).toUpperCase(),
              style: TextStyle(
                color: context.readerColors.onSurface,
                fontSize: AppTypography.displayLarge,
                height: 1,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 10),
            Text(
              readerTypeLabel(AppLocalizations.of(context), item.itemType),
              style: TextStyle(
                color: context.readerColors.onSurfaceVariant,
                fontSize: AppTypography.bodyMedium,
                height: 18 / 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 书籍详情页的阅读与书架操作区。
class ReaderDetailActions extends StatelessWidget {
  const ReaderDetailActions({
    required this.detail,
    required this.bookshelfBusy,
    required this.onToggleBookshelf,
    required this.onReadChapter,
    this.localPayload,
    this.alignment = Alignment.centerLeft,
    super.key,
  });

  final ReaderItemDetail detail;
  final bool bookshelfBusy;
  final VoidCallback onToggleBookshelf;
  final ValueChanged<ReaderChapter> onReadChapter;
  final Map<String, dynamic>? localPayload;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final item = detail.item;
    final localSnapshot = ReaderProgressSnapshot.fromLocal(localPayload);
    final serverSnapshot = ReaderProgressSnapshot.fromServer(detail.progress);
    final progressSnapshot = ReaderProgressSnapshot.latest(
      localSnapshot,
      serverSnapshot,
    );
    final hasProgress =
        progressSnapshot?.hasReadableProgress == true ||
        (detail.progress?.progressPercent ?? 0) > 0;

    final primaryButton = FilledButton.icon(
      onPressed:
          detail.chapters.isEmpty
              ? null
              : () {
                final chapter =
                    hasProgress
                        ? ReaderProgressSnapshot.resolveChapter(
                          detail.chapters,
                          progressSnapshot,
                        )
                        : detail.chapters.firstOrNull;
                if (chapter != null) {
                  onReadChapter(chapter);
                }
              },
      icon: Icon(
        hasProgress ? Icons.play_arrow_rounded : Icons.auto_stories_rounded,
        size: 20,
      ),
      label: Text(
        hasProgress
            ? AppLocalizations.of(context).readerContinueReading
            : AppLocalizations.of(context).readerStartReading,
      ),
      style: FilledButton.styleFrom(
        backgroundColor: context.readerColors.primaryContainer,
        foregroundColor: context.readerColors.onPrimaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
    final bookshelfButton = FilledButton(
      onPressed: bookshelfBusy ? null : onToggleBookshelf,
      style: FilledButton.styleFrom(
        backgroundColor:
            item.addedToBookshelf
                ? context.readerColors.primary.withValues(alpha: 0.12)
                : context.readerColors.surfaceContainerHigh,
        foregroundColor:
            item.addedToBookshelf
                ? context.readerColors.primary
                : context.readerColors.onSurfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child:
          bookshelfBusy
              ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: context.readerColors.onSurfaceVariant,
                ),
              )
              : Text(
                item.addedToBookshelf
                    ? AppLocalizations.of(context).readerAddedToBookshelf
                    : AppLocalizations.of(context).readerAddToBookshelf,
              ),
    );

    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 380) {
              return SizedBox(
                height: 100,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: primaryButton),
                    const SizedBox(height: 10),
                    Expanded(child: bookshelfButton),
                  ],
                ),
              );
            }
            return SizedBox(
              height: 44,
              child: Row(
                children: [
                  Expanded(child: primaryButton),
                  const SizedBox(width: 12),
                  Expanded(child: bookshelfButton),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 章节列表中的最小化章节条目（支持多级缩进和展开/折叠）
class MinimalChapterTile extends StatelessWidget {
  const MinimalChapterTile({
    required this.chapter,
    required this.onTap,
    this.isParent = false,
    this.isExpanded = true,
    this.onToggleExpand,
    super.key,
  });

  final ReaderChapter chapter;
  final VoidCallback onTap;

  /// 是否为包含子节点的父级卷标题
  final bool isParent;

  /// 父级节点是否展开（仅对 isParent=true 有意义）
  final bool isExpanded;

  /// 点击展开/折叠按钮的回调
  final VoidCallback? onToggleExpand;

  @override
  Widget build(BuildContext context) {
    final level = chapter.level;
    final isVolume = level == 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: isParent ? onToggleExpand : onTap,
        child: Padding(
          padding: EdgeInsets.only(
            left: 4.0 + level * 20.0,
            right: 4,
            top: isVolume ? 16 : 12,
            bottom: 12,
          ),
          child: Row(
            children: [
              if (!isVolume)
                Text(
                  chapter.chapterNumber.toStringAsFixed(
                    chapter.chapterNumber ==
                            chapter.chapterNumber.roundToDouble()
                        ? 0
                        : 1,
                  ),
                  style: TextStyle(
                    color: context.readerColors.onSurface.withValues(
                      alpha: 0.4,
                    ),
                    fontSize: AppTypography.bodySmall,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              if (!isVolume) SizedBox(width: 12),
              Expanded(
                child: Text(
                  chapter.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.readerColors.onSurface,
                    fontSize: isVolume ? 15 : 14,
                    fontWeight: isVolume ? FontWeight.w700 : FontWeight.w400,
                    height: 1.4,
                  ),
                ),
              ),
              if (isParent)
                GestureDetector(
                  onTap: onToggleExpand,
                  child: AnimatedRotation(
                    turns: isExpanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      color: context.readerColors.onSurface.withValues(
                        alpha: 0.5,
                      ),
                      size: 20,
                    ),
                  ),
                )
              else
                Icon(
                  Icons.chevron_right_rounded,
                  color: context.readerColors.onSurfaceVariant,
                  size: 18,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
