import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/reader_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/core/widgets/app_error_view.dart';
import 'package:omninest/core/widgets/app_loading.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/application/reader_comic_service.dart';
import 'package:omninest/features/reader/application/reader_book_provider.dart';
import 'package:omninest/features/reader/application/reader_local_progress.dart';
import 'package:omninest/features/reader/application/reader_progress_snapshot.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/domain/reader_status_constants.dart';
import 'package:omninest/features/reader/presentation/pages/comic_detail_page.dart';
import 'package:omninest/features/reader/presentation/reader_l10n_helpers.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_book_cover.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_page_scaffold.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_snack_bar.dart';
import 'package:omninest/core/errors/error_message.dart';

/// 阅读条目详情页：Hero（封面/进度/阅读动作）+ 简介/章节/批注/书签页签。
///
/// 文本与漫画条目均按参考设计重绘；漫画的目录树与来源管理由
/// ComicDetailPage 以同构布局承载。
class ReaderItemDetailPage extends ConsumerStatefulWidget {
  const ReaderItemDetailPage({required this.itemId, super.key});

  final String itemId;

  @override
  ConsumerState<ReaderItemDetailPage> createState() =>
      _ReaderItemDetailPageState();
}

class _ReaderItemDetailPageState extends ConsumerState<ReaderItemDetailPage> {
  bool _bookshelfBusy = false;

  void _handleBack() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/reader');
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(readerItemDetailProvider(widget.itemId));

    // 详情视图渲染在模块内容区域内（顶栏/侧栏/底导航保持可见），返回条为固定页头。
    // 漫画分支自带 Sliver 滚动体，声明后骨架不再二次包裹。
    return ReaderPageScaffold(
      target: ReaderPageTarget.library,
      enablePopGuard: false,
      childOwnScroll: detailAsync.asData?.value.item.isComic ?? false,
      headerPadding: EdgeInsets.zero,
      header: _DetailBackBar(onTap: _handleBack),
      child: detailAsync.when(
        data: (detail) {
          final isPdf =
              detail.item.itemType.toUpperCase() == 'PDF' &&
              !detail.item.isComic;
          if (isPdf) {
            return _PdfDetailContent(
              item: detail.item,
              progress: detail.progress,
              bookshelfBusy: _bookshelfBusy,
              onToggleBookshelf: _toggleBookshelf,
              onRead: () {
                context.push('/reader/pdfs/${detail.item.id}/read');
              },
              onEditMetadata:
                  () =>
                      context.push('/reader/items/${detail.item.id}/metadata'),
              onDelete: _deleteItem,
            );
          }
          final isComic = detail.item.isComic;
          if (isComic) {
            return _ComicDetailWrapper(
              item: detail.item,
              itemId: widget.itemId,
              progress: detail.progress,
              onEditMetadata:
                  () =>
                      context.push('/reader/items/${detail.item.id}/metadata'),
              onDelete: _deleteItem,
            );
          }

          final bookAsync = ref.watch(parsedBookProvider(widget.itemId));
          if (bookAsync.isLoading) {
            return AppLoading.detail();
          }
          if (bookAsync.hasError) {
            return AppErrorView(
              message: AppLocalizations.of(context).readerChapterLoadFailed,
              onRetry: () => ref.invalidate(parsedBookProvider(widget.itemId)),
            );
          }

          // 从本地解析获取章节列表（后端不返回章节）
          final parsedBook = bookAsync.asData?.value;
          final effectiveItem = _buildEffectiveItem(detail.item, parsedBook);

          return _TextDetailContent(
            item: effectiveItem,
            progress: detail.progress,
            chapters: parsedBook?.chapters ?? const [],
            bookshelfBusy: _bookshelfBusy,
            onToggleBookshelf: _toggleBookshelf,
            onReadChapter: (chapterId, {required resume}) {
              // 显式选章（目录/书签）进目标章章首（entry=chapter）；
              // 继续阅读不传 entry，走续读恢复（resume 意图）。
              context.push(
                '/reader/items/${detail.item.id}/chapters/$chapterId'
                '${resume ? '' : '?entry=chapter'}',
              );
            },
            onEditMetadata:
                () => context.push('/reader/items/${detail.item.id}/metadata'),
            onReparse: _reparse,
            onDelete: _deleteItem,
          );
        },
        error:
            (error, stackTrace) => AppErrorView(
              message: describeUserFacingError(error).message,
              onRetry:
                  () => ref.invalidate(readerItemDetailProvider(widget.itemId)),
            ),
        loading: () => AppLoading.detail(),
      ),
    );
  }

  Future<void> _toggleBookshelf() async {
    setState(() => _bookshelfBusy = true);
    try {
      await ref
          .read(readerCenterControllerProvider.notifier)
          .toggleBookshelf(widget.itemId);
      if (mounted) {
        ref.invalidate(readerItemDetailProvider(widget.itemId));
        ref.invalidate(readerCenterControllerProvider);
      }
    } on Exception {
      if (!mounted) return;
      showReaderSnackBar(
        context,
        AppLocalizations.of(context).readerOperationFailed,
      );
    } finally {
      if (mounted) {
        setState(() => _bookshelfBusy = false);
      }
    }
  }

  Future<void> _reparse() async {
    try {
      await ref
          .read(readerCenterControllerProvider.notifier)
          .reparseItem(widget.itemId);
      if (mounted) {
        ref.invalidate(readerItemDetailProvider(widget.itemId));
      }
    } on Exception {
      if (!mounted) return;
      showReaderSnackBar(
        context,
        AppLocalizations.of(context).readerOperationFailed,
      );
    }
  }

  Future<void> _deleteItem() async {
    final itemTitle =
        ref
            .read(readerItemDetailProvider(widget.itemId))
            .asData
            ?.value
            .item
            .title ??
        '';
    try {
      await ref
          .read(readerCenterControllerProvider.notifier)
          .deleteItem(widget.itemId);
      if (!mounted) return;
      showReaderSnackBar(
        context,
        AppLocalizations.of(context).readerDeletedItem(itemTitle),
      );
      context.go('/reader');
    } on Exception {
      if (!mounted) return;
      showReaderSnackBar(
        context,
        AppLocalizations.of(context).readerDeleteItemFailed,
      );
    }
  }

  /// 使用解析的元数据覆盖 API 数据（如果 API 数据是临时文件名）
  ReaderItem _buildEffectiveItem(ReaderItem apiItem, ParsedBook? parsedBook) {
    if (parsedBook == null) return apiItem;

    final parsedTitle = parsedBook.title;
    final parsedAuthor = parsedBook.author;
    final needsTitleUpdate =
        parsedTitle != null &&
        parsedTitle.isNotEmpty &&
        parsedTitle != apiItem.title;
    final needsAuthorUpdate =
        parsedAuthor != null &&
        parsedAuthor.isNotEmpty &&
        apiItem.authorName == null;

    if (!needsTitleUpdate && !needsAuthorUpdate) return apiItem;

    return ReaderItem(
      id: apiItem.id,
      createdAt: apiItem.createdAt,
      fileNodeId: apiItem.fileNodeId,
      itemType: apiItem.itemType,
      title: needsTitleUpdate ? parsedTitle : apiItem.title,
      authorName: needsAuthorUpdate ? parsedAuthor : apiItem.authorName,
      coverUrl: apiItem.coverUrl,
      description: apiItem.description,
      publisher: apiItem.publisher,
      language: apiItem.language,
      rating: apiItem.rating,
      progressPercent: apiItem.progressPercent,
      updatedAt: apiItem.updatedAt,
      addedToBookshelf: apiItem.addedToBookshelf,
      spaceType: apiItem.spaceType,
      currentChapterTitle: apiItem.currentChapterTitle,
      metadataStatus: apiItem.metadataStatus,
      releaseDate: apiItem.releaseDate,
      genres: apiItem.genres,
      serialStatus: apiItem.serialStatus,
      contentKind: apiItem.contentKind,
      importStatus: apiItem.importStatus,
      parseErrorCode: apiItem.parseErrorCode,
      parseErrorMessage: apiItem.parseErrorMessage,
    );
  }
}

enum _DetailTab { info, chapters, annotations, bookmarks }

class _TextDetailContent extends ConsumerStatefulWidget {
  const _TextDetailContent({
    required this.item,
    required this.progress,
    required this.chapters,
    required this.bookshelfBusy,
    required this.onToggleBookshelf,
    required this.onReadChapter,
    required this.onEditMetadata,
    required this.onReparse,
    required this.onDelete,
  });

  final ReaderItem item;
  final ReaderProgress? progress;
  final List<ParsedChapter> chapters;
  final bool bookshelfBusy;
  final VoidCallback onToggleBookshelf;
  final void Function(String chapterId, {required bool resume}) onReadChapter;
  final VoidCallback onEditMetadata;
  final VoidCallback onReparse;
  final VoidCallback onDelete;

  @override
  ConsumerState<_TextDetailContent> createState() => _TextDetailContentState();
}

class _TextDetailContentState extends ConsumerState<_TextDetailContent> {
  _DetailTab _tab = _DetailTab.info;
  ReaderProgressSnapshot? _progressSnapshot;

  @override
  void initState() {
    super.initState();
    _loadProgressSnapshot();
  }

  Future<void> _loadProgressSnapshot() async {
    final local = ReaderProgressSnapshot.fromLocal(
      await ReaderLocalProgress.loadLatest(widget.item.id),
    );
    final server = ReaderProgressSnapshot.fromServer(widget.progress);
    if (!mounted) return;
    setState(() {
      _progressSnapshot = ReaderProgressSnapshot.latest(local, server);
    });
  }

  List<ReaderChapter> _readerChapters() {
    return widget.chapters
        .asMap()
        .entries
        .map(
          (e) => ReaderChapter.fromParsed(
            e.key,
            e.value.title,
            contentPath: e.value.contentPath,
            level: e.value.level,
          ),
        )
        .toList();
  }

  void _startReading() {
    final chapters = _readerChapters();
    final chapter = ReaderProgressSnapshot.resolveChapter(
      chapters,
      _progressSnapshot,
    );
    if (chapter != null) {
      widget.onReadChapter(chapter.id, resume: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHero(context),
        const SizedBox(height: 32),
        _buildTabBar(context),
        const SizedBox(height: 24),
        _buildTabContent(context),
      ],
    );
  }

  Widget _buildHero(BuildContext context) {
    final rc = context.readerColors;
    final l10n = AppLocalizations.of(context);
    final item = widget.item;
    final progress = (item.progressPercent ?? 0).clamp(0.0, 1.0);
    final complete = progress >= 1;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 144,
          height: 216,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: ReaderBookCover(item: item, size: ReaderCoverSize.large),
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                readerTypeLabel(l10n, item.itemType),
                style: TextStyle(
                  color: rc.onSurfaceVariant,
                  // ignore: font_size_whitelist
                  fontSize: 10,
                  height: 1.2,
                  letterSpacing: 2.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                item.title,
                style: TextStyle(
                  color: rc.onSurface,
                  fontSize: AppTypography.headlineMedium,
                  height: 1.25,
                  fontFamily: kReaderSerifFamily,
                ),
              ),
              if (item.authorName?.isNotEmpty == true) ...[
                const SizedBox(height: 4),
                Text(
                  item.authorName!,
                  style: TextStyle(
                    color: rc.onSurfaceVariant,
                    fontSize: AppTypography.bodyMedium,
                    height: 1.3,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Text(
                    l10n.readerDetailProgress,
                    style: TextStyle(
                      color: rc.onSurfaceVariant,
                      fontSize: AppTypography.bodySmall,
                      height: 1.2,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    complete
                        ? l10n.readerDetailComplete
                        : '${(progress * 100).round()}%',
                    style: TextStyle(
                      color: complete ? rc.reading : rc.onSurface,
                      fontSize: AppTypography.bodySmall,
                      height: 1.2,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                height: 2,
                color: rc.outlineVariant,
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: progress,
                  child: Container(height: 2, color: rc.reading),
                ),
              ),
              const SizedBox(height: 20),
              _buildActionRow(context),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionRow(BuildContext context) {
    final rc = context.readerColors;
    final l10n = AppLocalizations.of(context);
    final hasProgress = _progressSnapshot?.hasReadableProgress == true;
    final primaryLabel =
        hasProgress ? l10n.readerContinueReading : l10n.readerStartReading;
    return Wrap(
      spacing: 12,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilledButton.icon(
          onPressed: widget.chapters.isEmpty ? null : () => _startReading(),
          icon: const Icon(Icons.play_arrow_rounded, size: 18),
          label: Text(primaryLabel),
          style: FilledButton.styleFrom(
            backgroundColor: rc.primary,
            foregroundColor: rc.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(2),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
        ),
        OutlinedButton.icon(
          onPressed: widget.bookshelfBusy ? null : widget.onToggleBookshelf,
          icon: Icon(
            widget.item.addedToBookshelf
                ? Icons.bookmark_rounded
                : Icons.bookmark_add_rounded,
            size: 18,
            color:
                widget.item.addedToBookshelf
                    ? rc.onSurface
                    : rc.onSurfaceVariant,
          ),
          label: Text(
            widget.item.addedToBookshelf
                ? l10n.readerAddedToBookshelf
                : l10n.readerAddToBookshelf,
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(
              color:
                  widget.item.addedToBookshelf
                      ? rc.onSurface
                      : rc.outlineVariant,
            ),
            foregroundColor:
                widget.item.addedToBookshelf
                    ? rc.onSurface
                    : rc.onSurfaceVariant,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(2),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
        PopupMenuButton<String>(
          tooltip: AppLocalizations.of(context).coreMore,
          icon: Icon(Icons.more_horiz_rounded, color: rc.onSurfaceVariant),
          onSelected: (value) {
            if (value == 'metadata') widget.onEditMetadata();
            if (value == 'reparse') widget.onReparse();
            if (value == 'delete') _confirmDelete(context);
          },
          itemBuilder:
              (context) => [
                PopupMenuItem(
                  value: 'metadata',
                  child: Text(l10n.readerDetailEditMeta),
                ),
                PopupMenuItem(
                  value: 'reparse',
                  child: Text(l10n.readerDetailReparse),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    l10n.readerDeleteBook,
                    style: TextStyle(color: rc.danger),
                  ),
                ),
              ],
        ),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(l10n.readerConfirmDelete),
            content: Text(l10n.readerConfirmDeleteMsg(widget.item.title)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(l10n.coreCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: FilledButton.styleFrom(
                  backgroundColor: context.readerColors.danger,
                ),
                child: Text(l10n.filesDelete),
              ),
            ],
          ),
    );
    if (confirmed == true) {
      widget.onDelete();
    }
  }

  Widget _buildTabBar(BuildContext context) {
    final rc = context.readerColors;
    final l10n = AppLocalizations.of(context);
    final tabs = {
      _DetailTab.info: l10n.readerDetailInfo,
      _DetailTab.chapters: l10n.readerDetailChapters,
      _DetailTab.annotations: l10n.readerDetailAnnotations,
      _DetailTab.bookmarks: l10n.readerDetailBookmarks,
    };
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: rc.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final entry in tabs.entries)
              InkWell(
                onTap: () => setState(() => _tab = entry.key),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  height: 40,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color:
                            _tab == entry.key
                                ? rc.onSurface
                                : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    entry.value,
                    style: TextStyle(
                      fontSize: AppTypography.bodyMedium,
                      height: 1.2,
                      fontWeight:
                          _tab == entry.key ? FontWeight.w600 : FontWeight.w400,
                      color:
                          _tab == entry.key
                              ? rc.onSurface
                              : rc.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabContent(BuildContext context) {
    switch (_tab) {
      case _DetailTab.info:
        return _buildInfoTab(context);
      case _DetailTab.chapters:
        return _buildChaptersTab(context);
      case _DetailTab.annotations:
        return _buildAnnotationsTab(context);
      case _DetailTab.bookmarks:
        return _buildBookmarksTab(context);
    }
  }

  Widget _buildInfoTab(BuildContext context) {
    final rc = context.readerColors;
    final l10n = AppLocalizations.of(context);
    final item = widget.item;
    final wordCount = widget.chapters.fold<int>(
      0,
      (sum, c) => sum + c.charCount,
    );
    final lastReadAt = _progressSnapshot?.updatedAt ?? item.updatedAt;
    final rows = <(String, String)>[
      (l10n.readerDetailType, readerTypeLabel(l10n, item.itemType)),
      if (item.language?.isNotEmpty == true)
        (l10n.readerDetailLanguage, item.language!.toUpperCase()),
      (
        l10n.readerDetailWords,
        '${wordCount >= 1000 ? '${wordCount ~/ 1000}k' : wordCount}',
      ),
      if (item.createdAt != null)
        (l10n.readerDetailAdded, _formatDateTime(item.createdAt!)),
      if (lastReadAt != null)
        (l10n.readerDetailLastRead, _formatDateTime(lastReadAt)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.description?.isNotEmpty == true
              ? item.description!
              : l10n.readerNoDescription,
          style: TextStyle(
            color: rc.onSurface.withValues(alpha: 0.8),
            fontSize: AppTypography.bodyMedium,
            height: 1.7,
          ),
        ),
        const SizedBox(height: 24),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                SizedBox(
                  width: 110,
                  child: Text(
                    row.$1,
                    style: TextStyle(
                      color: rc.onSurfaceVariant,
                      fontSize: AppTypography.labelSmall,
                      height: 1.2,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    row.$2,
                    style: TextStyle(
                      color: rc.onSurface,
                      fontSize: AppTypography.bodyMedium,
                      height: 1.3,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildChaptersTab(BuildContext context) {
    final rc = context.readerColors;
    final l10n = AppLocalizations.of(context);
    final chapters = widget.chapters;
    if (chapters.isEmpty) {
      return Text(
        l10n.readerNoDescription,
        style: TextStyle(
          color: rc.onSurfaceVariant,
          fontSize: AppTypography.bodySmall,
        ),
      );
    }
    final currentChapterId =
        _progressSnapshot?.hasReadableProgress == true
            ? _progressSnapshot!.chapterId
            : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < chapters.length; i++)
          InkWell(
            onTap: () => widget.onReadChapter('chapter_$i', resume: false),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: Text(
                      '${i + 1}'.padLeft(2, '0'),
                      style: TextStyle(
                        color: rc.onSurfaceVariant,
                        // ignore: font_size_whitelist
                        fontSize: 10,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      chapters[i].title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: rc.onSurface,
                        fontSize: AppTypography.bodyMedium,
                        height: 1.3,
                        fontWeight:
                            'chapter_$i' == currentChapterId
                                ? FontWeight.w700
                                : FontWeight.w400,
                      ),
                    ),
                  ),
                  if ('chapter_$i' == currentChapterId) ...[
                    const SizedBox(width: 8),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: rc.reading,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    _estimateMinutes(chapters[i].charCount),
                    style: TextStyle(
                      color: rc.onSurfaceVariant,
                      // ignore: font_size_whitelist
                      fontSize: 10,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  String _estimateMinutes(int charCount) {
    final minutes = (charCount / 500).ceil().clamp(1, 999);
    return '$minutes ${AppLocalizations.of(context).readerDetailMinRead}';
  }

  Widget _buildAnnotationsTab(BuildContext context) {
    final rc = context.readerColors;
    final l10n = AppLocalizations.of(context);
    final annotationsAsync = ref.watch(
      readerItemAnnotationsProvider(widget.item.id),
    );
    return annotationsAsync.when(
      loading: () => const SizedBox.shrink(),
      error:
          (_, _) => Text(
            l10n.readerOperationFailed,
            style: TextStyle(
              color: rc.onSurfaceVariant,
              fontSize: AppTypography.bodySmall,
            ),
          ),
      data: (annotations) {
        if (annotations.isEmpty) {
          return Text(
            l10n.readerDetailNoAnn,
            style: TextStyle(
              color: rc.onSurfaceVariant,
              fontSize: AppTypography.bodySmall,
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final ann in annotations)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: _parseColor(ann.color), width: 2),
                    ),
                  ),
                  padding: const EdgeInsets.only(left: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ann.highlightText ?? '',
                        style: TextStyle(
                          color: rc.onSurface,
                          fontSize: AppTypography.bodyMedium,
                          height: 1.6,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      if (ann.note?.isNotEmpty == true) ...[
                        const SizedBox(height: 6),
                        Text(
                          ann.note!,
                          style: TextStyle(
                            color: rc.onSurfaceVariant,
                            fontSize: AppTypography.labelSmall,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Color _parseColor(String? colorStr) {
    final hex = colorStr?.replaceAll('#', '');
    if (hex == null || hex.length != 6) {
      return context.readerColors.reading;
    }
    return Color(int.parse('FF$hex', radix: 16));
  }

  Widget _buildBookmarksTab(BuildContext context) {
    final rc = context.readerColors;
    final l10n = AppLocalizations.of(context);
    final bookmarksAsync = ref.watch(
      readerItemBookmarksProvider(widget.item.id),
    );
    return bookmarksAsync.when(
      loading: () => const SizedBox.shrink(),
      error:
          (_, _) => Text(
            l10n.readerOperationFailed,
            style: TextStyle(
              color: rc.onSurfaceVariant,
              fontSize: AppTypography.bodySmall,
            ),
          ),
      data: (bookmarks) {
        if (bookmarks.isEmpty) {
          return Text(
            l10n.readerDetailNoBm,
            style: TextStyle(
              color: rc.onSurfaceVariant,
              fontSize: AppTypography.bodySmall,
            ),
          );
        }
        return Column(
          children: [
            for (final bookmark in bookmarks)
              InkWell(
                onTap:
                    () => widget.onReadChapter(
                      _resolveBookmarkChapterId(bookmark),
                      resume: false,
                    ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Icon(Icons.bookmark_rounded, size: 14, color: rc.reading),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          bookmark.note?.isNotEmpty == true
                              ? bookmark.note!
                              : widget.item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: rc.onSurface,
                            fontSize: AppTypography.bodyMedium,
                            height: 1.3,
                          ),
                        ),
                      ),
                      if (bookmark.createdAt != null)
                        Text(
                          _formatDateTime(bookmark.createdAt!),
                          style: TextStyle(
                            color: rc.onSurfaceVariant,
                            // ignore: font_size_whitelist
                            fontSize: 10,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  String _resolveBookmarkChapterId(ReaderBookmark bookmark) {
    final snapshotChapterId = _progressSnapshot?.chapterId;
    if (snapshotChapterId != null && snapshotChapterId.isNotEmpty) {
      return snapshotChapterId;
    }
    return 'chapter_0';
  }

  String _formatDateTime(DateTime time) {
    final y = time.year.toString();
    final m = time.month.toString().padLeft(2, '0');
    final d = time.day.toString().padLeft(2, '0');
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }
}

/// PDF 详情：无服务端章节清单，直接进入客户端渲染阅读器。
class _PdfDetailContent extends StatelessWidget {
  const _PdfDetailContent({
    required this.item,
    required this.progress,
    required this.bookshelfBusy,
    required this.onToggleBookshelf,
    required this.onRead,
    required this.onEditMetadata,
    required this.onDelete,
  });

  final ReaderItem item;
  final ReaderProgress? progress;
  final bool bookshelfBusy;
  final VoidCallback onToggleBookshelf;
  final VoidCallback onRead;
  final VoidCallback onEditMetadata;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final percent =
        ((progress?.progressPercent ?? 0) * 100).clamp(0, 100).toDouble();
    // 内容较短，随骨架滚动体滚动；不自带 ListView 以免嵌套滚动。
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(item.title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            '${readerTypeLabel(l10n, item.itemType)}'
            '${item.authorName == null ? '' : ' · ${item.authorName}'}',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(value: percent / 100),
          const SizedBox(height: 8),
          Text(readerProgressLabelText(l10n, percent)),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onRead,
            icon: const Icon(Icons.menu_book_outlined),
            label: Text(l10n.readerPdfTitle),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: bookshelfBusy ? null : onToggleBookshelf,
            icon: Icon(
              item.addedToBookshelf
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_add_rounded,
            ),
            label: Text(
              item.addedToBookshelf
                  ? l10n.readerAddedToBookshelf
                  : l10n.readerAddToBookshelf,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: onEditMetadata,
            child: Text(l10n.readerEditMetadata),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => _confirmDelete(context),
            child: Text(l10n.readerDeleteBook),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(l10n.readerConfirmDelete),
            content: Text(l10n.readerConfirmDeleteMsg(item.title)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(l10n.coreCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(dialogContext).colorScheme.error,
                ),
                child: Text(l10n.filesDelete),
              ),
            ],
          ),
    );
    if (!context.mounted || confirmed != true) {
      return;
    }
    onDelete();
  }
}

/// 漫画详情包装器 — 加载清单后将目录节点传递给 ComicDetailPage。
class _ComicDetailWrapper extends ConsumerWidget {
  const _ComicDetailWrapper({
    required this.item,
    required this.itemId,
    this.progress,
    this.onEditMetadata,
    this.onDelete,
  });

  final ReaderItem item;
  final String itemId;
  final ReaderProgress? progress;
  final VoidCallback? onEditMetadata;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monitor = ref.watch(comicManifestMonitorProvider(itemId));
    final manifest = monitor.asData?.value.manifest;
    if (manifest == null && monitor.asData?.value.refreshError == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (manifest == null) {
      return AppErrorView(
        message: AppLocalizations.of(context).readerRefreshFailed,
        onRetry: () => ref.invalidate(comicManifestMonitorProvider(itemId)),
      );
    }
    final terminal =
        manifest.importStatus != ReaderImportStatus.pending &&
        manifest.importStatus != ReaderImportStatus.parsing;
    if (terminal && item.isParsing) {
      // 后端已终态而本地解析标志未跟上：限流兜底刷新一次，避免以
      // 网络往返为周期的零间隔隐式轮询。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Timer(const Duration(milliseconds: 500), () {
          if (context.mounted) {
            ref.invalidate(readerItemDetailProvider(itemId));
          }
        });
      });
    }
    // 外层详情页已提供 ReaderPageScaffold（页头/滚动/材质）；
    // 此处再嵌一层会在无界约束下产生嵌套 Scaffold 布局错误。
    return ComicDetailPage(
      item: item,
      chapters: manifest.catalog,
      pages: manifest.pages,
      sources: manifest.sources,
      progress: progress,
      canRead: manifest.pages.isNotEmpty,
      parseProgress: manifest.parseTask?.progress,
      onRetrySource: (source) => _retryComicSource(context, ref, source),
      onDeleteSource: (source) => _deleteComicSource(context, ref, source),
      onEditMetadata: onEditMetadata,
      onDelete: onDelete,
    );
  }

  Future<bool> _retryComicSource(
    BuildContext context,
    WidgetRef ref,
    ComicSource source,
  ) async {
    final ok = await ref
        .read(readerComicServiceProvider)
        .retrySource(itemId, source.id);
    if (ok && context.mounted) {
      ref.invalidate(comicManifestMonitorProvider(itemId));
    }
    return ok;
  }

  Future<bool> _deleteComicSource(
    BuildContext context,
    WidgetRef ref,
    ComicSource source,
  ) async {
    try {
      await ref
          .read(readerComicServiceProvider)
          .deleteSource(itemId, source.id);
      if (!context.mounted) {
        return true;
      }
      ref.invalidate(comicManifestMonitorProvider(itemId));
      ref.invalidate(readerItemDetailProvider(itemId));
      await ref.read(comicManifestMonitorProvider(itemId).future);
      return true;
    } on Exception {
      return false;
    }
  }
}

/// 详情页固定页头返回条：通栏底边框，点击区域仅按钮内容。
class _DetailBackBar extends StatelessWidget {
  const _DetailBackBar({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rc = context.readerColors;
    final l10n = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: rc.outlineVariant)),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: 48,
            padding: EdgeInsets.symmetric(
              horizontal: MediaQuery.sizeOf(context).width >= 1024 ? 32 : 24,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.arrow_back_rounded,
                  size: 16,
                  color: rc.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.coreBack,
                  style: TextStyle(
                    color: rc.onSurfaceVariant,
                    fontSize: AppTypography.bodyMedium,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
