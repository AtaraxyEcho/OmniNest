import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/reader_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/widgets/responsive_breakpoints.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/application/reader_local_progress.dart';
import 'package:omninest/features/reader/application/reader_progress_snapshot.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/reader_l10n_helpers.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_book_cover.dart';

enum _DetailTab { info, chapters, annotations, bookmarks }

/// 正文条目详情：Hero（封面/进度/阅读动作）+ 简介/章节/批注/书签页签。
///
/// 页级滚动体由本类持有（ReaderPageScaffold 以 childOwnScroll 声明），
/// 章节/批注/书签按 sliver 懒建。
class ReaderDetailTextContent extends ConsumerStatefulWidget {
  const ReaderDetailTextContent({
    required this.item,
    required this.progress,
    required this.chapters,
    required this.bookshelfBusy,
    required this.onToggleBookshelf,
    required this.onReadChapter,
    required this.onEditMetadata,
    required this.onReparse,
    required this.onDelete,
    super.key,
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
  ConsumerState<ReaderDetailTextContent> createState() =>
      ReaderDetailTextContentState();
}

class ReaderDetailTextContentState
    extends ConsumerState<ReaderDetailTextContent> {
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
    // 页级滚动体：章节/批注/书签可达上千条，必须按 sliver 懒建而非 Column 全量构建。
    // 内边距沿用 ReaderPageScaffold 未声明 childOwnScroll 时的取值。
    final wide =
        MediaQuery.sizeOf(context).width >= ResponsiveBreakpoints.workbenchRail;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(wide ? 32 : 24, 24, wide ? 32 : 24, 40),
          sliver: SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(child: _buildHero(context)),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
              SliverToBoxAdapter(child: _buildTabBar(context)),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
              _buildTabContent(context),
            ],
          ),
        ),
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

  /// 页签内容统一以 sliver 返回：正文分支的滚动体在本类内，懒建依赖 sliver 协议。
  Widget _buildTabContent(BuildContext context) {
    switch (_tab) {
      case _DetailTab.info:
        return SliverToBoxAdapter(child: _buildInfoTab(context));
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
    return SliverList.builder(
      itemCount: chapters.length,
      itemBuilder: (context, i) {
        return InkWell(
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
        );
      },
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
      loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
      error:
          (_, _) => SliverToBoxAdapter(
            child: Text(
              l10n.readerOperationFailed,
              style: TextStyle(
                color: rc.onSurfaceVariant,
                fontSize: AppTypography.bodySmall,
              ),
            ),
          ),
      data: (annotations) {
        if (annotations.isEmpty) {
          return SliverToBoxAdapter(
            child: Text(
              l10n.readerDetailNoAnn,
              style: TextStyle(
                color: rc.onSurfaceVariant,
                fontSize: AppTypography.bodySmall,
              ),
            ),
          );
        }
        return SliverList.builder(
          itemCount: annotations.length,
          itemBuilder: (context, index) {
            final ann = annotations[index];
            return Padding(
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
            );
          },
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
      loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
      error:
          (_, _) => SliverToBoxAdapter(
            child: Text(
              l10n.readerOperationFailed,
              style: TextStyle(
                color: rc.onSurfaceVariant,
                fontSize: AppTypography.bodySmall,
              ),
            ),
          ),
      data: (bookmarks) {
        if (bookmarks.isEmpty) {
          return SliverToBoxAdapter(
            child: Text(
              l10n.readerDetailNoBm,
              style: TextStyle(
                color: rc.onSurfaceVariant,
                fontSize: AppTypography.bodySmall,
              ),
            ),
          );
        }
        return SliverList.builder(
          itemCount: bookmarks.length,
          itemBuilder: (context, index) {
            final bookmark = bookmarks[index];
            return InkWell(
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
            );
          },
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
