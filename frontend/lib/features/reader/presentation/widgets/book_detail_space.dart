import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/core/widgets/omni_icons.dart';
import 'package:omninest/core/widgets/app_error_view.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/features/reader/application/reader_book_provider.dart';
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
  final void Function(String chapterId, {required bool resume, int? charOffset})
  onReadChapter;

  final Future<void> Function() onToggleBookshelf;
  final bool bookshelfBusy;

  /// 当前是否已在书架（决定心形按钮激活态）。
  final bool bookshelfAdded;

  @override
  ConsumerState<BookDetailSpace> createState() => _BookDetailSpaceState();
}

class _BookDetailSpaceState extends ConsumerState<BookDetailSpace> {
  bool _aboutExpanded = false;
  ReaderProgressSnapshot? _localSnapshot;

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
    setState(() => _localSnapshot = snapshot);
  }

  /// 开始/继续阅读：与桌面详情同源，先取服务端清单，再取本地与服务端进度里
  /// 较新的一份定位章节。清单为空（仍在解析或解析失败）时不发起跳转。
  void _startReading(
    List<ReaderChapter> chapters,
    ReaderProgress? serverProgress,
  ) {
    final snapshot = ReaderProgressSnapshot.latest(
      _localSnapshot,
      ReaderProgressSnapshot.fromServer(serverProgress),
    );
    final chapter = ReaderProgressSnapshot.resolveChapter(chapters, snapshot);
    if (chapter == null) {
      return;
    }
    widget.onReadChapter(
      chapter.id,
      resume: snapshot?.hasReadableProgress ?? false,
    );
  }

  /// 章节清单来源：详情响应不含章节（后端不存目录），此前只读 `detail.chapters`
  /// 时清单恒空，"开始阅读"因此静默无响应、目录整块消失。
  static List<ReaderChapter> _chaptersOf(AsyncValue<ParsedBook> bookAsync) {
    final parsed = bookAsync.asData?.value.chapters;
    if (parsed == null) {
      return const <ReaderChapter>[];
    }
    return parsed
        .asMap()
        .entries
        .map((entry) => ReaderChapter.fromParsed(entry.key, entry.value))
        .toList();
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
        final bookAsync = ref.watch(parsedBookProvider(widget.itemId));
        final chapters = _chaptersOf(bookAsync);
        return ListView(
          // 样例 `.book-detail-scroll` 内衬 18px 20px 30px。
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
          children: [
            // 样例 `.book-identity` 的块内另有 5px 水平内缩。
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: _BookIdentity(item: item, chapterCount: chapters.length),
            ),
            const SizedBox(height: 26),
            _BookActions(
              hasProgress: progress > 0,
              busy: widget.bookshelfBusy,
              bookshelfAdded: widget.bookshelfAdded,
              onRead:
                  chapters.isEmpty
                      ? null
                      : () => _startReading(chapters, detail.progress),
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
            _ChapterSection(
              bookAsync: bookAsync,
              chapters: chapters,
              progress: progress,
              onRetry: () => ref.invalidate(parsedBookProvider(widget.itemId)),
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
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.horizontal(
              left: Radius.circular(3),
              right: Radius.circular(14),
            ),
            boxShadow: [
              BoxShadow(
                color: context.env.readerCoverSpine,
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
        const SizedBox(width: 24),
        // 样例 `.book-identity` 是 align-items:center：右侧信息列垂直居中
        // 于 175 高的书封，不再靠顶边偏移对齐。
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                l10n.bookDetailInLibrary.toUpperCase(),
                style: TextStyle(
                  color: context.env.accentInk,
                  fontSize: AppTypography.labelMicro,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.3,
                ),
              ),
              // 样例 `.book-identity h1` margin 9px 0 5px，p 的余下边距 14px。
              const SizedBox(height: 9),
              Text(
                item.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.env.ink,
                  fontFamily: AppTypography.serifFamily,
                  fontFamilyFallback: AppTypography.serifFamilyFallback,
                  fontSize: AppTypography.headlineLarge,
                  height: 1.02,
                  fontWeight: FontWeight.w400,
                ),
              ),
              if (item.authorName?.isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    item.authorName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.env.inkMuted,
                      fontSize: AppTypography.bodyMedium,
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              Text(
                l10n.bookDetailMeta(item.itemType.toUpperCase(), chapterCount),
                style: TextStyle(
                  color: context.env.inkMuted,
                  fontSize: AppTypography.labelSmall,
                ),
              ),
            ],
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
    return ColoredBox(color: context.env.readerCoverBg);
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

  /// 清单未就绪（仍在解析或解析失败）时为 null：按钮转灰，不给按下去没反应的入口。
  final VoidCallback? onRead;
  final VoidCallback onToggleBookshelf;
  final VoidCallback onMetadata;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.env.line13)),
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
                  color: context.env.accent,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: context.env.accent.withValues(alpha: 0.32),
                      blurRadius: 14,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OmniIcon(
                      icon: OmniIcons.book,
                      size: 18,
                      color: context.env.onAccent,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        hasProgress
                            ? l10n.bookDetailContinue
                            : l10n.bookDetailStart,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.env.onAccent,
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
            color: context.env.line07,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: context.env.line09),
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
                      color: active ? context.env.accentInk : context.env.ink,
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
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.env.line13)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.bookDetailProgressLabel,
                style: TextStyle(
                  color: context.env.inkMuted,
                  fontSize: AppTypography.labelSmall,
                ),
              ),
              Text(
                '${(percent * 100).round()}%',
                style: TextStyle(
                  color: context.env.ink,
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
              color: context.env.accentInk,
              backgroundColor: context.env.line10,
            ),
          ),
          if (lastOpened.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              l10n.bookDetailLastOpened(lastOpened),
              style: TextStyle(
                color: context.env.inkMuted,
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
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.env.line13)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.bookDetailAbout.toUpperCase(),
            style: TextStyle(
              color: context.env.inkMuted,
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
            style: TextStyle(
              color: context.env.inkMuted,
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
              foregroundColor: context.env.accentInk,
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

/// 目录区块的状态外壳：清单就绪列章节，仍在解析给静态骨架，解析失败给重试入口。
///
/// 三态都要占住同一块位置：直接塌成 `SizedBox.shrink()` 时，读者分不清
/// "书还在后台解析"和"这本书没有目录"，也没有任何重试入口。
class _ChapterSection extends StatelessWidget {
  const _ChapterSection({
    required this.bookAsync,
    required this.chapters,
    required this.progress,
    required this.onRetry,
    required this.onOpenChapter,
  });

  final AsyncValue<ParsedBook> bookAsync;
  final List<ReaderChapter> chapters;
  final double progress;
  final VoidCallback onRetry;
  final ValueChanged<String> onOpenChapter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (chapters.isNotEmpty) {
      return _ChapterList(
        chapters: chapters,
        progress: progress,
        onOpenChapter: onOpenChapter,
      );
    }
    final failure = bookAsync.error;
    if (failure != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _ContentsHeader(),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    describeUserFacingError(failure).message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.env.inkMuted,
                      fontSize: AppTypography.labelSmall,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onRetry,
                  style: TextButton.styleFrom(
                    foregroundColor: context.env.ink,
                    minimumSize: const Size(48, 38),
                  ),
                  child: Text(l10n.readerRetry),
                ),
              ],
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _ContentsHeader(),
          const SizedBox(height: 14),
          for (final width in <double>[1.0, 0.82, 0.68])
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: MobileSkeletonBlock(height: 16, width: width * 320),
            ),
        ],
      ),
    );
  }
}

/// 目录区块的标题排（CONTENTS + 章节数）。清单未就绪时章节数为空。
class _ContentsHeader extends StatelessWidget {
  const _ContentsHeader({this.chapterCount});

  final int? chapterCount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.bookDetailContents.toUpperCase(),
                style: TextStyle(
                  color: context.env.white43,
                  fontSize: AppTypography.labelMicro,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                l10n.bookDetailChapters,
                style: TextStyle(
                  color: context.env.ink,
                  fontSize: AppTypography.titleLarge,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
        ),
        if (chapterCount != null)
          TextButton(
            onPressed: null,
            style: TextButton.styleFrom(
              foregroundColor: context.env.white70,
              minimumSize: const Size(48, 38),
              textStyle: const TextStyle(fontSize: AppTypography.labelSmall),
            ),
            child: Text(l10n.bookDetailChapterCount(chapterCount!)),
          ),
      ],
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
    // 只列顶级章节（卷级 level 0）。
    final topLevel = chapters.where((chapter) => chapter.level == 0).toList();
    final effective = topLevel.isEmpty ? chapters : topLevel;
    final readCount = (progress * effective.length).floor();
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ContentsHeader(chapterCount: effective.length),
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
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: context.env.line07)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: Text(
                (index + 1).toString().padLeft(2, '0'),
                style: TextStyle(
                  color: context.env.ink40,
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
                    style: TextStyle(
                      color: context.env.ink,
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
                        style: TextStyle(
                          color: context.env.inkMuted,
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
              color: read ? context.env.accentInk : context.env.inkMuted,
            ),
          ],
        ),
      ),
    );
  }
}
