import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_routes.dart';
import 'package:omninest/app/desktop/desktop_toast.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_dialogs.dart';
import 'package:omninest/app/desktop/widgets/desktop_skeleton.dart';
import 'package:omninest/app/desktop/widgets/desktop_surfaces.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/utils/route_exit.dart';
import 'package:omninest/core/widgets/workstation_dialog.dart';

import 'desktop_book_metadata_dialog.dart';
import 'package:omninest/features/reader/reader_dashboard.dart';

/// 书目详情的四个页签（样例 `BookDetail`：About / Chapters / Notes / Activity）。
/// 从主页面拆出，主页只负责英雄区与统计条，避免单文件越过 800 行闸门。
class DesktopBookDetailTabs extends ConsumerStatefulWidget {
  const DesktopBookDetailTabs({
    required this.item,
    required this.chapters,
    required this.progress,
    required this.onOpenChapter,
    required this.onRetryChapters,
    this.chaptersLoading = false,
    this.chaptersError = false,
    super.key,
  });

  final ReaderItem item;
  final List<ReaderChapter> chapters;
  final ReaderProgress? progress;
  final ValueChanged<ReaderChapter> onOpenChapter;

  /// 章节清单来自 `/text/manifest`，解析未完成时给骨架而不是空态。
  final bool chaptersLoading;
  final bool chaptersError;
  final VoidCallback onRetryChapters;

  @override
  ConsumerState<DesktopBookDetailTabs> createState() =>
      _DesktopBookDetailTabsState();
}

class _DesktopBookDetailTabsState extends ConsumerState<DesktopBookDetailTabs> {
  int _tab = 0;
  bool _busy = false;
  bool _showFullDescription = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: DesktopSeg<int>(
            options: const [0, 1, 2, 3],
            value: _tab,
            small: true,
            labelOf:
                (value) => switch (value) {
                  0 => l10n.readerDetailInfo,
                  1 => l10n.readerDetailChapters,
                  2 => l10n.readerNavNotes,
                  _ => l10n.desktopBookActivity,
                },
            onChanged: (value) => setState(() => _tab = value),
          ),
        ),
        const SizedBox(height: 20),
        switch (_tab) {
          0 => _overview(l10n, skin),
          1 => _chapters(l10n, skin),
          2 => _notes(l10n, skin),
          _ => _activity(l10n, skin),
        },
      ],
    );
  }

  Widget _overview(AppLocalizations l10n, DesktopSkin skin) {
    final item = widget.item;
    final genres = item.genres ?? const <String>[];
    final description = (item.description ?? '').trim();
    // 样例始终把描述限制在三行，展开状态只作用于这段描述，不能把
    // 详情页其它分区一起撑开；短描述仍保留同一处 Read more 操作位。
    final canExpandDescription = description.isNotEmpty;
    final about = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: AnimatedSize(
            duration: DesktopMotion.fade,
            curve: DesktopMotion.ease,
            alignment: Alignment.topLeft,
            child: Text(
              description.isEmpty ? l10n.desktopMoviesNoOverview : description,
              key: ValueKey(
                '${_showFullDescription ? 'expanded' : 'collapsed'}:$description',
              ),
              maxLines:
                  canExpandDescription && !_showFullDescription ? 3 : null,
              overflow:
                  canExpandDescription && !_showFullDescription
                      ? TextOverflow.ellipsis
                      : TextOverflow.visible,
              style: DesktopType.body(skin.text2),
            ),
          ),
        ),
        if (canExpandDescription)
          DesktopLink(
            label:
                _showFullDescription
                    ? l10n.desktopMoviesShowLess
                    : l10n.desktopMoviesReadMore,
            trailing: false,
            onPressed:
                () => setState(
                  () => _showFullDescription = !_showFullDescription,
                ),
          ),
        if (genres.isNotEmpty) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final genre in genres) DesktopChip(genre)],
          ),
        ],
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            DesktopButton(
              label: l10n.desktopBookEditMetadata,
              icon: DesktopIcons.edit,
              variant: DesktopButtonVariant.soft,
              onPressed: _busy ? null : _editMetadata,
            ),
            DesktopButton(
              label: l10n.desktopBookReparse,
              icon: DesktopIcons.restore,
              variant: DesktopButtonVariant.soft,
              busy: _busy,
              onPressed: _busy ? null : _reparse,
            ),
            DesktopButton(
              label: l10n.desktopBookRemove,
              icon: DesktopIcons.close,
              variant: DesktopButtonVariant.ghost,
              onPressed: _busy ? null : _remove,
            ),
          ],
        ),
      ],
    );
    final spec = Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: skin.panel,
        borderRadius: BorderRadius.circular(DesktopMetrics.radiusCard),
        border: Border.all(color: skin.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.desktopBookDetails, style: DesktopType.eyebrow(skin.text3)),
          const SizedBox(height: 12),
          _specRow(skin, l10n.desktopBookFormat, item.itemType),
          _specRow(skin, l10n.desktopBookContent, item.contentKind),
          _specRow(
            skin,
            l10n.desktopBookPublisher,
            (item.publisher ?? '').trim().isEmpty ? '—' : item.publisher!,
          ),
          _specRow(
            skin,
            l10n.desktopBookLanguage,
            (item.language ?? '').trim().isEmpty ? '—' : item.language!,
          ),
          _specRow(
            skin,
            l10n.desktopBookParsing,
            (item.importStatus ?? '').trim().isEmpty
                ? (item.parseErrorCode ?? l10n.desktopBookReadable)
                : item.importStatus!,
          ),
          _specRow(
            skin,
            l10n.desktopBookAdded,
            item.createdAt == null ? '—' : _shortDate(item.createdAt!),
          ),
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // 原型在 1180px 以下才把 bp-grid 堆成单列；900px 会让中等桌面窗
        // 的说明和详情卡过早改成纵向，导致与样例的 1.3fr/1fr 网格脱节。
        if (constraints.maxWidth < 1180) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [about, const SizedBox(height: 20), spec],
          );
        }
        final specWidth = math.max(280.0, (constraints.maxWidth - 40) / 2.3);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: about),
            const SizedBox(width: 40),
            SizedBox(width: specWidth, child: spec),
          ],
        );
      },
    );
  }

  Widget _specRow(DesktopSkin skin, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(label, style: DesktopType.caption(skin.text3)),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: DesktopType.dense(skin.text),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chapters(AppLocalizations l10n, DesktopSkin skin) {
    if (widget.chaptersLoading && widget.chapters.isEmpty) {
      return const DesktopSkeletonRows(count: 6, avatar: false);
    }
    if (widget.chaptersError && widget.chapters.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _placeholder(l10n.readerChapterLoadFailed),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: DesktopButton(
              label: l10n.coreRetry,
              variant: DesktopButtonVariant.ghost,
              onPressed: widget.onRetryChapters,
            ),
          ),
        ],
      );
    }
    if (widget.chapters.isEmpty) {
      return _placeholder(l10n.desktopBookNoChapters);
    }
    return Container(
      decoration: BoxDecoration(
        color: skin.panel,
        borderRadius: BorderRadius.circular(DesktopMetrics.radiusCard),
        border: Border.all(color: skin.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < widget.chapters.length; i++)
            _ChapterRow(
              chapter: widget.chapters[i],
              index: i,
              current: widget.chapters[i].id == widget.progress?.chapterId,
              first: i == 0,
              onTap: () => widget.onOpenChapter(widget.chapters[i]),
            ),
        ],
      ),
    );
  }

  Widget _notes(AppLocalizations l10n, DesktopSkin skin) {
    final annotations = ref.watch(
      readerItemAnnotationsProvider(widget.item.id),
    );
    final bookmarks = ref.watch(readerItemBookmarksProvider(widget.item.id));
    final loading =
        annotations.isLoading && !annotations.hasValue ||
        bookmarks.isLoading && !bookmarks.hasValue;
    if (loading) {
      return const DesktopSkeletonRows(count: 3, avatar: false);
    }
    final marks = annotations.asData?.value ?? const <ReaderAnnotation>[];
    final saved = bookmarks.asData?.value ?? const <ReaderBookmark>[];
    if (marks.isEmpty && saved.isEmpty) {
      return _placeholder(l10n.desktopBookNoNotes);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final mark in marks)
          _NoteCard(
            quote: mark.highlightText ?? '',
            note: mark.note ?? '',
            meta:
                '${mark.chapterId ?? l10n.desktopBookHighlight}'
                '${mark.createdAt == null ? '' : ' · ${_shortDate(mark.createdAt!)}'}',
            color: _parseColor(mark.color),
          ),
        for (final bookmark in saved)
          _NoteCard(
            quote: bookmark.chapterTitle ?? l10n.desktopBookBookmark,
            note: bookmark.note ?? '',
            meta:
                '${(bookmark.progressPercent).round()}%'
                '${bookmark.createdAt == null ? '' : ' · ${_shortDate(bookmark.createdAt!)}'}',
            color: skin.warm,
            bookmark: true,
          ),
      ],
    );
  }

  Widget _activity(AppLocalizations l10n, DesktopSkin skin) {
    final stats = ref.watch(readerStatsOverviewProvider);
    return stats.when(
      loading: () => const DesktopSkeletonRows(count: 3, avatar: false),
      error:
          (error, _) => _placeholder(
            failureToast(l10n, l10n.desktopBookNoActivity, error),
          ),
      data: (value) {
        final days =
            value.dailyMinutes.length > 7
                ? value.dailyMinutes.sublist(value.dailyMinutes.length - 7)
                : value.dailyMinutes;
        if (days.isEmpty) {
          return _placeholder(l10n.desktopBookNoActivity);
        }
        final maxMinutes = days
            .map((day) => day.minutes)
            .fold<int>(1, math.max);
        return Container(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
          decoration: BoxDecoration(
            color: skin.panel,
            borderRadius: BorderRadius.circular(DesktopMetrics.radiusCard),
            border: Border.all(color: skin.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.desktopBookActivityScope,
                style: DesktopType.caption(skin.text3),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 120,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final day in days)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: FractionallySizedBox(
                                    heightFactor: (day.minutes / maxMinutes)
                                        .clamp(0.04, 1.0),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: skin.accent.withValues(
                                          alpha: 0.8,
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _weekday(day.date),
                                style: DesktopType.nano(skin.text3),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                l10n.desktopBookActivitySummary(
                  value.completedCount,
                  value.inProgressCount,
                ),
                style: DesktopType.caption(skin.text3),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _placeholder(String message) {
    final skin = DesktopSkin.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 24),
      decoration: BoxDecoration(
        color: skin.panel,
        borderRadius: BorderRadius.circular(DesktopMetrics.radiusCard),
        border: Border.all(color: skin.line),
      ),
      child: Column(
        children: [
          Icon(DesktopIcons.book, size: 22, color: skin.text3),
          const SizedBox(height: 10),
          Text(message, style: DesktopType.dense(skin.text2)),
        ],
      ),
    );
  }

  Future<void> _editMetadata() async {
    final l10n = AppLocalizations.of(context);
    // 样例 MetaEditor 是右侧抽屉（`ui.tsx` 的 Drawer + Portal 全窗口 scrim）。
    final saved = await showDesktopDrawer<bool>(
      context,
      width: 480,
      builder: (_) => DesktopBookMetadataDrawer(item: widget.item),
    );
    if (saved == true && mounted) {
      ref.invalidate(readerItemDetailProvider(widget.item.id));
      showDesktopToast(
        context,
        l10n.desktopBookMetadataSaved,
        kind: DesktopToastKind.success,
      );
    }
  }

  Future<void> _reparse() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDesktopConfirm(
      context,
      title: l10n.desktopBookReparse,
      message: l10n.desktopBookReparseConfirm,
      confirmLabel: l10n.desktopBookReparse,
      cancelLabel: l10n.coreCancel,
    );
    if (!confirmed || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(readerCenterControllerProvider.notifier)
          .reparseItem(widget.item.id);
      if (!mounted) {
        return;
      }
      ref.invalidate(readerItemDetailProvider(widget.item.id));
      ref.invalidate(readerDashboardProvider);
      showDesktopToast(
        context,
        l10n.desktopBookReparsed,
        kind: DesktopToastKind.success,
      );
    } on Object catch (error) {
      if (mounted) {
        showDesktopToast(
          context,
          errorReason(error, l10n),
          kind: DesktopToastKind.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _remove() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showWorkstationDestructiveConfirm(
      context,
      title: l10n.desktopBookRemove,
      message: l10n.desktopBookRemoveMessage,
      confirmPhrase: widget.item.title,
      confirmLabel: l10n.desktopBookRemove,
    );
    if (!confirmed || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(readerCenterControllerProvider.notifier)
          .deleteItem(widget.item.id, cascade: false);
      if (!mounted) {
        return;
      }
      showDesktopToast(
        context,
        l10n.desktopBookRemoved,
        kind: DesktopToastKind.success,
      );
      exitDetailRoute(context, fallbackRoute: DesktopRoutes.reader);
    } on Object catch (error) {
      if (mounted) {
        showDesktopToast(
          context,
          errorReason(error, l10n),
          kind: DesktopToastKind.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.quote,
    required this.note,
    required this.meta,
    required this.color,
    this.bookmark = false,
  });

  final String quote;
  final String note;
  final String meta;
  final Color color;
  final bool bookmark;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: skin.panel,
        borderRadius: BorderRadius.circular(DesktopMetrics.radius),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (bookmark) ...[
                Icon(DesktopIcons.bookmark, size: 14, color: color),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  quote,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: DesktopType.body(skin.text),
                ),
              ),
            ],
          ),
          if (note.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(note, style: DesktopType.dense(skin.text2)),
          ],
          const SizedBox(height: 6),
          Text(meta, style: DesktopType.caption(skin.text3)),
        ],
      ),
    );
  }
}

class _ChapterRow extends StatelessWidget {
  const _ChapterRow({
    required this.chapter,
    required this.index,
    required this.current,
    required this.first,
    required this.onTap,
  });

  final ReaderChapter chapter;
  final int index;
  final bool current;
  final bool first;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    return DesktopHover(
      builder:
          (context, hovered) => GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: hovered ? skin.raise : Colors.transparent,
                border:
                    first ? null : Border(top: BorderSide(color: skin.line)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${index + 1}',
                      style: DesktopType.numeric(skin.text3),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      chapter.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DesktopType.dense(
                        current ? skin.accent : skin.text,
                      ).copyWith(
                        fontWeight: current ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (current)
                    Text(
                      l10n.readerContinueReading,
                      style: DesktopType.caption(skin.accent),
                    )
                  else if (chapter.pageCount != null)
                    Text(
                      '${chapter.pageCount}',
                      style: DesktopType.nano(skin.text3),
                    ),
                ],
              ),
            ),
          ),
    );
  }
}

Color _parseColor(String value) {
  final hex = value.replaceFirst('#', '');
  final parsed = int.tryParse(hex, radix: 16);
  if (parsed == null) {
    return Colors.amber;
  }
  return Color(hex.length <= 6 ? 0xFF000000 | parsed : parsed);
}

String _shortDate(DateTime value) {
  final local = value.toLocal();
  String two(int part) => part.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)}';
}

String _weekday(DateTime value) {
  const names = ['一', '二', '三', '四', '五', '六', '日'];
  return names[(value.weekday - 1).clamp(0, 6)];
}
