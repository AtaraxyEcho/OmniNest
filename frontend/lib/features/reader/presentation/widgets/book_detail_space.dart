import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/mobile_env_colors.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/core/widgets/omni_icons.dart';
import 'package:omninest/core/widgets/app_error_view.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_cover_image.dart';
import 'package:omninest/features/reader/application/reader_local_progress.dart';
import 'package:omninest/features/reader/application/reader_progress_snapshot.dart';

/// 书籍详情页（原型 BookDetail 1:1 的移动壳层形态）。
///
/// 结构：纸色大书封 + 书籍身份 → 动作排（继续阅读主按钮 + 书架/元数据
/// 方钮）→ 阅读进度 → 关于本书（衬线节选 + 展开更多）→ 章节目录（衬线
/// 序号 + 已读对勾）。
class BookDetailSpace extends ConsumerStatefulWidget {
  const BookDetailSpace({
    required this.itemId,
    required this.onReadChapter,
    required this.onToggleBookshelf,
    required this.bookshelfBusy,
    required this.bookshelfAdded,
    super.key,
  });

  final String itemId;

  /// 打开指定章节（resume=true 走续读恢复）。
  final void Function(String chapterId, {required bool resume}) onReadChapter;

  final Future<void> Function() onToggleBookshelf;
  final bool bookshelfBusy;

  /// 当前是否已在书架（决定心形按钮激活态）。
  final bool bookshelfAdded;

  @override
  ConsumerState<BookDetailSpace> createState() => _BookDetailSpaceState();
}

class _BookDetailSpaceState extends ConsumerState<BookDetailSpace> {
  bool _aboutExpanded = false;
  String? _resumeChapterId;

  @override
  void initState() {
    super.initState();
    _resolveResumeChapter();
  }

  Future<void> _resolveResumeChapter() async {
    final snapshot = ReaderProgressSnapshot.fromLocal(
      await ReaderLocalProgress.loadLatest(widget.itemId),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _resumeChapterId =
          snapshot.hasReadableProgress ? snapshot.chapterId : null;
    });
  }

  void _startReading() {
    final chapterId = _resumeChapterId;
    if (chapterId != null && chapterId.isNotEmpty) {
      widget.onReadChapter(chapterId, resume: true);
      return;
    }
    final detail =
        ref.read(readerItemDetailProvider(widget.itemId)).asData?.value;
    final chapters = detail?.chapters ?? const <ReaderChapter>[];
    if (chapters.isNotEmpty) {
      widget.onReadChapter(chapters.first.id, resume: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(readerItemDetailProvider(widget.itemId));
    return detailAsync.when(
      loading: () => const MobileSkeletonBlock(height: 320),
      error:
          (error, _) => AppErrorView(
            message: describeUserFacingError(error).message,
            onRetry:
                () => ref.invalidate(readerItemDetailProvider(widget.itemId)),
          ),
      data: (detail) {
        final item = detail.item;
        final progress = item.progressPercent ?? 0.0;
        final chapters = detail.chapters;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            _BookIdentity(item: item, chapterCount: chapters.length),
            const SizedBox(height: 20),
            _BookActions(
              hasProgress: progress > 0,
              busy: widget.bookshelfBusy,
              bookshelfAdded: widget.bookshelfAdded,
              onRead: _startReading,
              onToggleBookshelf: () => unawaited(widget.onToggleBookshelf()),
              onMetadata:
                  () => context.push('/reader/items/${item.id}/metadata'),
            ),
            if (progress > 0) ...[_BookProgress(percent: progress, item: item)],
            _BookAbout(
              description: item.description ?? '',
              expanded: _aboutExpanded,
              onToggle: () => setState(() => _aboutExpanded = !_aboutExpanded),
            ),
            _ChapterList(
              chapters: chapters,
              progress: progress,
              onOpenChapter: (chapterId) {
                widget.onReadChapter(chapterId, resume: false);
              },
            ),
          ],
        );
      },
    );
  }
}

/// 书籍身份排：124×175 纸色书封 + 右侧元信息。
class _BookIdentity extends StatelessWidget {
  const _BookIdentity({required this.item, required this.chapterCount});

  final int chapterCount;

  final ReaderItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.horizontal(
              left: Radius.circular(3),
              right: Radius.circular(14),
            ),
            boxShadow: [
              BoxShadow(
                color: MobileEnvColors.readerCoverSpine,
                offset: Offset(-5, 0),
              ),
              BoxShadow(
                color: Colors.black45,
                blurRadius: 30,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(3),
              right: Radius.circular(14),
            ),
            child: SizedBox(
              width: 124,
              height: 175,
              child:
                  item.hasCover
                      ? AuthCoverImage(
                        itemId: item.id,
                        fit: BoxFit.cover,
                        fallback: const _PaperIdentityCover(),
                      )
                      : const _PaperIdentityCover(),
            ),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.bookDetailInLibrary.toUpperCase(),
                  style: const TextStyle(
                    color: MobileEnvColors.accent,
                    fontSize: AppTypography.labelMicro,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.3,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  item.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: MobileEnvColors.ink,
                    fontFamily: AppTypography.serifFamily,
                    fontFamilyFallback: AppTypography.serifFamilyFallback,
                    fontSize: AppTypography.displaySmall,
                    height: 1.02,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (item.authorName?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      item.authorName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: MobileEnvColors.inkMuted,
                        fontSize: AppTypography.bodyMedium,
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                Text(
                  l10n.bookDetailMeta(
                    item.itemType.toUpperCase(),
                    chapterCount,
                  ),
                  style: const TextStyle(
                    color: MobileEnvColors.inkMuted,
                    fontSize: AppTypography.labelSmall,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 无封面时的纸色身份书封（衬线书名 + 作者）。
class _PaperIdentityCover extends StatelessWidget {
  const _PaperIdentityCover();

  @override
  Widget build(BuildContext context) {
    // 由父级 ClipRRect 提供尺寸；此处仅铺纸色与细纹。
    return const ColoredBox(color: MobileEnvColors.readerCoverBg);
  }
}

/// 动作排：lime 主按钮（继续/开始阅读）+ 两个 50px 方钮。
class _BookActions extends StatelessWidget {
  const _BookActions({
    required this.hasProgress,
    required this.busy,
    required this.bookshelfAdded,
    required this.onRead,
    required this.onToggleBookshelf,
    required this.onMetadata,
  });

  final bool hasProgress;
  final bool busy;
  final bool bookshelfAdded;
  final VoidCallback onRead;
  final VoidCallback onToggleBookshelf;
  final VoidCallback onMetadata;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.only(bottom: 24),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: MobileEnvColors.line13)),
      ),
      child: Row(
        children: [
          Expanded(
            child: MobilePressable(
              semanticLabel:
                  hasProgress ? l10n.bookDetailContinue : l10n.bookDetailStart,
              onTap: onRead,
              child: Container(
                height: 50,
                decoration: BoxDecoration(
                  color: MobileEnvColors.accent,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: MobileEnvColors.accent.withValues(alpha: 0.32),
                      blurRadius: 14,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const OmniIcon(
                      icon: OmniIcons.book,
                      size: 18,
                      color: MobileEnvColors.onAccent,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        hasProgress
                            ? l10n.bookDetailContinue
                            : l10n.bookDetailStart,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: MobileEnvColors.onAccent,
                          fontSize: AppTypography.labelSmall,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _SquareAction(
            icon: OmniIcons.heart,
            tooltip: l10n.readerNavBookshelf,
            active: bookshelfAdded,
            busy: busy,
            onTap: onToggleBookshelf,
          ),
          const SizedBox(width: 8),
          _SquareAction(
            icon: OmniIcons.settings,
            tooltip: l10n.bookDetailMetadata,
            onTap: onMetadata,
          ),
        ],
      ),
    );
  }
}

class _SquareAction extends StatelessWidget {
  const _SquareAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
    this.busy = false,
  });

  final OmniIconsData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: MobilePressable(
        semanticLabel: tooltip,
        onTap: busy ? null : onTap,
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: const Color(0x14FFFFFF)),
          ),
          child: Center(
            child:
                busy
                    ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : OmniIcon(
                      icon: icon,
                      size: 19,
                      color:
                          active ? MobileEnvColors.accent : MobileEnvColors.ink,
                    ),
          ),
        ),
      ),
    );
  }
}

/// 阅读进度区：标签行 + 3px 进度 + 最近打开时间。
class _BookProgress extends StatelessWidget {
  const _BookProgress({required this.percent, required this.item});

  final double percent;
  final ReaderItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final localizations = MaterialLocalizations.of(context);
    final updated = item.updatedAt;
    final lastOpened =
        updated == null ? '' : localizations.formatShortDate(updated);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 23),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: MobileEnvColors.line13)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.bookDetailProgressLabel,
                style: const TextStyle(
                  color: MobileEnvColors.inkMuted,
                  fontSize: AppTypography.labelSmall,
                ),
              ),
              Text(
                '${(percent * 100).round()}%',
                style: const TextStyle(
                  color: MobileEnvColors.ink,
                  fontSize: AppTypography.labelSmall,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: percent.clamp(0, 1),
              minHeight: 3,
              color: MobileEnvColors.accent,
              backgroundColor: const Color(0x1AFFFFFF),
            ),
          ),
          if (lastOpened.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              l10n.bookDetailLastOpened(lastOpened),
              style: const TextStyle(
                color: MobileEnvColors.inkMuted,
                fontSize: AppTypography.labelMicro,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 关于本书：衬线节选 + 展开更多。
class _BookAbout extends StatelessWidget {
  const _BookAbout({
    required this.description,
    required this.expanded,
    required this.onToggle,
  });

  final String description;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (description.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.only(top: 24, bottom: 21),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: MobileEnvColors.line13)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.bookDetailAbout.toUpperCase(),
            style: const TextStyle(
              color: MobileEnvColors.inkMuted,
              fontSize: AppTypography.labelMicro,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            description,
            maxLines: expanded ? null : 3,
            overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xBDFFFFFF),
              fontFamily: AppTypography.serifFamily,
              fontFamilyFallback: AppTypography.serifFamilyFallback,
              fontSize: AppTypography.titleMedium,
              height: 1.48,
            ),
          ),
          const SizedBox(height: 7),
          TextButton(
            onPressed: onToggle,
            style: TextButton.styleFrom(
              foregroundColor: MobileEnvColors.accent,
              minimumSize: const Size(48, 38),
              padding: EdgeInsets.zero,
              alignment: Alignment.centerLeft,
              textStyle: const TextStyle(fontSize: AppTypography.labelSmall),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  expanded ? l10n.bookDetailShowLess : l10n.bookDetailShowMore,
                ),
                const OmniIcon(icon: OmniIcons.chevron, size: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 章节目录：CONTENTS 头 + 衬线序号行 + 已读对勾。
class _ChapterList extends StatelessWidget {
  const _ChapterList({
    required this.chapters,
    required this.progress,
    required this.onOpenChapter,
  });

  final List<ReaderChapter> chapters;
  final double progress;
  final ValueChanged<String> onOpenChapter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (chapters.isEmpty) {
      return const SizedBox.shrink();
    }
    // 只列顶级章节（卷级 level 0）。
    final topLevel = chapters.where((chapter) => chapter.level == 0).toList();
    final effective = topLevel.isEmpty ? chapters : topLevel;
    final readCount = (progress * effective.length).floor();
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.bookDetailContents.toUpperCase(),
                      style: const TextStyle(
                        color: MobileEnvColors.white43,
                        fontSize: AppTypography.labelMicro,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      l10n.bookDetailChapters,
                      style: const TextStyle(
                        color: MobileEnvColors.ink,
                        fontSize: AppTypography.titleLarge,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: null,
                style: TextButton.styleFrom(
                  foregroundColor: MobileEnvColors.white70,
                  minimumSize: const Size(48, 38),
                  textStyle: const TextStyle(
                    fontSize: AppTypography.labelSmall,
                  ),
                ),
                child: Text(l10n.bookDetailChapterCount(effective.length)),
              ),
            ],
          ),
          for (var index = 0; index < effective.length; index++)
            _ChapterRow(
              chapter: effective[index],
              index: index,
              read: index < readCount,
              onOpen: () => onOpenChapter(effective[index].id),
            ),
        ],
      ),
    );
  }
}

class _ChapterRow extends StatelessWidget {
  const _ChapterRow({
    required this.chapter,
    required this.index,
    required this.read,
    required this.onOpen,
  });

  final ReaderChapter chapter;
  final int index;
  final bool read;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final label = chapter.title.isNotEmpty ? chapter.title : '${index + 1}';
    return MobilePressable(
      semanticLabel: label,
      onTap: onOpen,
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0x12FFFFFF))),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: Text(
                (index + 1).toString().padLeft(2, '0'),
                style: const TextStyle(
                  color: Color(0x59FFFFFF),
                  fontFamily: AppTypography.serifFamily,
                  fontFamilyFallback: AppTypography.serifFamilyFallback,
                  fontSize: AppTypography.titleMedium,
                ),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: MobileEnvColors.ink,
                      fontSize: AppTypography.labelSmall,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (chapter.pageCount != null && chapter.pageCount! > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        AppLocalizations.of(
                          context,
                        ).bookDetailChapterPages(chapter.pageCount!),
                        style: const TextStyle(
                          color: MobileEnvColors.inkMuted,
                          fontSize: AppTypography.labelMicro,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            OmniIcon(
              icon: read ? OmniIcons.check : OmniIcons.chevron,
              size: 17,
              color: read ? MobileEnvColors.accent : MobileEnvColors.inkMuted,
            ),
          ],
        ),
      ),
    );
  }
}
