import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omninest/app/desktop/desktop_backdrop_layer.dart';
import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_routes.dart';
import 'package:omninest/app/desktop/desktop_router_scope.dart';
import 'package:omninest/app/desktop/desktop_toast.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_cover.dart';
import 'package:omninest/app/desktop/widgets/desktop_skeleton.dart';
import 'package:omninest/app/desktop/widgets/desktop_surfaces.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/utils/route_exit.dart';
import 'package:omninest/features/reader/reader_dashboard.dart';

import 'desktop_book_detail_sections.dart';
import 'desktop_book_related_rail.dart';

/// 桌面书籍详情（样例 `BookDetail`）：26 圆角英雄区 + 五格统计条 +
/// 概览/章节两页。章节列表来自客户端解析，阅读进度按服务端 progress 标记。
class DesktopBookDetailPage extends ConsumerWidget {
  const DesktopBookDetailPage({required this.itemId, super.key});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final detail = ref.watch(readerItemDetailProvider(itemId));
    // 章节清单走 parsedBookProvider（GET /text/manifest），与移动端书详同源。
    // detail.chapters 只在后端将来补字段或测试桩注入时才非空。
    final bookAsync = ref.watch(parsedBookProvider(itemId));

    return ColoredBox(
      color:
          desktopBackdropVisibleForRoute(ref, DesktopRoutes.bookDetail(itemId))
              ? Colors.transparent
              : skin.bg,
      child: detail.when(
        loading:
            () => const Center(
              child: SizedBox(
                width: 320,
                child: DesktopSkeletonRows(count: 6, avatar: false),
              ),
            ),
        error:
            (error, _) => Center(
              child: Text(
                failureToast(l10n, l10n.readerChapterLoadFailed, error),
                style: DesktopType.body(skin.text3),
              ),
            ),
        data: (value) {
          final item = value.item;
          final progress = value.progress;
          final percent = (progress?.progressPercent ??
                  item.progressPercent ??
                  0)
              .toDouble()
              .clamp(0.0, 100.0);
          final parsed = bookAsync.asData?.value.chapters;
          final chapters =
              value.chapters.isNotEmpty
                  ? value.chapters
                  : <ReaderChapter>[
                    if (parsed != null)
                      for (var i = 0; i < parsed.length; i++)
                        ReaderChapter.fromParsed(i, parsed[i]),
                  ];
          final chaptersLoading = chapters.isEmpty && bookAsync.isLoading;
          final chaptersError = chapters.isEmpty && bookAsync.hasError;
          final currentIndex = chapters.indexWhere(
            (chapter) => chapter.id == progress?.chapterId,
          );
          final hasProgress = percent > 0;
          final formatLabel =
              item.isComic
                  ? '${item.readerType == 'MANGA' ? 'MANGA' : 'COMIC'} · ${item.itemType}'
                  : item.itemType;
          final progressLabel =
              chapters.isEmpty
                  ? l10n.readerProgressPercent(percent.round())
                  : l10n.readerChapterPosition(
                    (currentIndex < 0 ? 0 : currentIndex) + 1,
                    chapters.length,
                  );
          final canOpenReader =
              item.isComic ||
              item.itemType.toUpperCase() == 'PDF' ||
              chapters.isNotEmpty;
          final tone = Color.lerp(skin.panelSolid, skin.accent, 0.24)!;

          return SingleChildScrollView(
            child: DesktopPage(
              topPadding: DesktopMetrics.pageTopPaddingCompact,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: DesktopLink(
                    label: l10n.desktopReaderLibrary,
                    icon: DesktopIcons.left,
                    trailing: false,
                    onPressed:
                        () =>
                            exitDetailRoute(context, fallbackRoute: '/reader'),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  clipBehavior: Clip.antiAlias,
                  // 样例 `.bp-hero { padding: 36px 44px; gap: 40px }`。
                  padding: const EdgeInsets.symmetric(
                    horizontal: 44,
                    vertical: 36,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [tone, skin.panelSolid],
                    ),
                    borderRadius: BorderRadius.circular(
                      DesktopMetrics.radiusHero,
                    ),
                    boxShadow: skin.shadow,
                  ),
                  foregroundDecoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      DesktopMetrics.radiusHero,
                    ),
                    border: Border.all(color: skin.line2),
                  ),
                  child: LayoutBuilder(
                    builder: (context, heroConstraints) {
                      final stacked = heroConstraints.maxWidth < 860;
                      return Flex(
                        direction: stacked ? Axis.vertical : Axis.horizontal,
                        crossAxisAlignment:
                            stacked
                                ? CrossAxisAlignment.start
                                : CrossAxisAlignment.center,
                        children: [
                          // 样例 `.bp-cover`：200×300，静止 -14deg，hover 收到 -4deg。
                          DesktopBookTilt(
                            child: _BookCover(item: item, large: true),
                          ),
                          SizedBox(
                            width: stacked ? 0 : 40,
                            height: stacked ? 24 : 0,
                          ),
                          Flexible(
                            fit: FlexFit.loose,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    DesktopChip(formatLabel, solid: true),
                                    if (item.rating != null)
                                      DesktopChip(
                                        '★ ${item.rating!.toStringAsFixed(1)}',
                                      ),
                                    if (percent >= 90)
                                      DesktopChip(l10n.readerStatusCompleted),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  item.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: DesktopType.displayXl(
                                    skin.text,
                                    MediaQuery.sizeOf(context).width,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  item.authorName ?? '',
                                  style: DesktopType.dense(skin.text2),
                                ),
                                const SizedBox(height: 18),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 420,
                                  ),
                                  child: _ProgressBar(value: percent / 100),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  progressLabel,
                                  style: DesktopType.caption(skin.text3),
                                ),
                                const SizedBox(height: 22),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    DesktopButton(
                                      label:
                                          hasProgress
                                              ? l10n.readerContinueReading
                                              : l10n.readerStartReading,
                                      icon: DesktopIcons.book,
                                      variant: DesktopButtonVariant.primary,
                                      large: true,
                                      onPressed:
                                          !canOpenReader
                                              ? null
                                              : () => _openReading(
                                                context,
                                                item,
                                                itemId,
                                                chapters,
                                                progress,
                                                resume: hasProgress,
                                              ),
                                    ),
                                    if (hasProgress)
                                      DesktopButton(
                                        label: l10n.desktopMoviesFromStart,
                                        variant: DesktopButtonVariant.glass,
                                        large: true,
                                        onPressed:
                                            !canOpenReader
                                                ? null
                                                : () => _openReading(
                                                  context,
                                                  item,
                                                  itemId,
                                                  chapters,
                                                  null,
                                                  resume: false,
                                                ),
                                      ),
                                    _DesktopBookShelfButton(item: item),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),
                _MetaStrip(
                  percent: percent,
                  chapters: chapters.length,
                  currentIndex: currentIndex,
                  item: item,
                ),
                const SizedBox(height: 22),
                DesktopBookDetailTabs(
                  item: item,
                  chapters: chapters,
                  progress: progress,
                  chaptersLoading: chaptersLoading,
                  chaptersError: chaptersError,
                  onRetryChapters:
                      () => ref.invalidate(parsedBookProvider(itemId)),
                  onOpenChapter:
                      (chapter) => _openReading(
                        context,
                        item,
                        itemId,
                        chapters,
                        progress,
                        resume: false,
                        chapter: chapter,
                      ),
                ),
                const SizedBox(height: 28),
                DesktopBookRelatedRail(item: item),
              ],
            ),
          );
        },
      ),
    );
  }

  void _openReading(
    BuildContext context,
    ReaderItem item,
    String itemId,
    List<ReaderChapter> chapters,
    ReaderProgress? progress, {
    required bool resume,
    ReaderChapter? chapter,
  }) {
    final encodedId = Uri.encodeComponent(itemId);
    if (item.isComic) {
      desktopPush(context, '/reader/comics/$encodedId/read');
      return;
    }
    if (item.itemType.toUpperCase() == 'PDF') {
      desktopPush(context, '/reader/pdfs/$encodedId/read');
      return;
    }
    _openChapter(
      context,
      itemId,
      chapters,
      progress,
      resume: resume,
      chapter: chapter,
    );
  }

  void _openChapter(
    BuildContext context,
    String itemId,
    List<ReaderChapter> chapters,
    ReaderProgress? progress, {
    required bool resume,
    ReaderChapter? chapter,
  }) {
    final current =
        chapter ??
        chapters
            .where((entry) => entry.id == progress?.chapterId)
            .firstOrNull ??
        chapters.first;
    final query = <String, String>{};
    if (resume && (progress?.charOffset ?? 0) > 0) {
      query['entry'] = 'offset';
      query['offset'] = '${progress!.charOffset}';
    } else if (!resume) {
      query['entry'] = 'chapter';
    }
    final suffix = query.isEmpty ? '' : '?${Uri(queryParameters: query).query}';
    desktopPush(
      context,
      '/reader/items/${Uri.encodeComponent(itemId)}/chapters/'
      '${Uri.encodeComponent(current.id)}$suffix',
    );
  }
}

class _BookCover extends StatelessWidget {
  const _BookCover({required this.item, this.large = false});

  final ReaderItem item;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: large ? 200 : 120,
      height: large ? 300 : 180,
      child: DesktopReaderBookCover(
        itemId: item.id,
        title: item.title,
        author: item.authorName ?? '',
        coverUrl: item.coverUrl,
        isComic: item.isDisplayedAsComic,
        readerType: item.readerType,
        volumeNumber: item.volumeNumber,
        large: large,
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 6,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: skin.raise3)),
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: value.clamp(0.0, 1.0),
                  child: ColoredBox(color: skin.accent),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaStrip extends StatelessWidget {
  const _MetaStrip({
    required this.percent,
    required this.chapters,
    required this.currentIndex,
    required this.item,
  });

  final double percent;
  final int chapters;
  final int currentIndex;
  final ReaderItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final progressMeta =
        chapters == 0
            ? l10n.readerProgressPercent(percent.round())
            : l10n.readerChapterPosition(
              (currentIndex < 0 ? 0 : currentIndex) + 1,
              chapters,
            );
    final cells = <(String, String, String)>[
      (l10n.desktopBookProgress, '${percent.round()}%', progressMeta),
      (l10n.desktopBookChapters, '$chapters', ''),
      (l10n.videoRating, item.rating?.toStringAsFixed(1) ?? '—', ''),
      (
        l10n.desktopBookAdded,
        item.createdAt == null ? '—' : _shortDate(item.createdAt!),
        '',
      ),
      (l10n.desktopBookFormat, item.itemType, item.contentKind),
    ];
    return Container(
      decoration: BoxDecoration(
        color: skin.panel,
        borderRadius: BorderRadius.circular(DesktopMetrics.radiusCard),
        border: Border.all(color: skin.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          for (var i = 0; i < cells.length; i++)
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  border:
                      i == 0
                          ? null
                          : Border(left: BorderSide(color: skin.line)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      cells[i].$1.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DesktopType.eyebrow(skin.text3),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      cells[i].$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DesktopType.sectionTitle(skin.text),
                    ),
                    if (cells[i].$3.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        cells[i].$3,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DesktopType.caption(skin.text3),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 详情英雄区的书架收藏动作：使用真实 `addedToBookshelf` 状态，避免把
/// 原型的局部收藏按钮做成只在当前窗口生效的假状态。
class _DesktopBookShelfButton extends ConsumerStatefulWidget {
  const _DesktopBookShelfButton({required this.item});

  final ReaderItem item;

  @override
  ConsumerState<_DesktopBookShelfButton> createState() =>
      _DesktopBookShelfButtonState();
}

class _DesktopBookShelfButtonState
    extends ConsumerState<_DesktopBookShelfButton> {
  bool _busy = false;

  Future<void> _toggle() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    final l10n = AppLocalizations.of(context);
    try {
      final result = await ref
          .read(readerCenterControllerProvider.notifier)
          .setBookshelf(
            widget.item.id,
            onBookshelf: !widget.item.addedToBookshelf,
          );
      if (!mounted) {
        return;
      }
      ref.invalidate(readerItemDetailProvider(widget.item.id));
      showDesktopToast(
        context,
        result.addedToBookshelf
            ? l10n.readerAddedToBookshelf
            : l10n.readerRemovedFromBookshelf,
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final added = widget.item.addedToBookshelf;
    return DesktopButton.iconOnly(
      icon: added ? DesktopIcons.bookmarkFilled : DesktopIcons.bookmark,
      variant: DesktopButtonVariant.soft,
      large: true,
      active: added,
      foregroundOverride: added ? DesktopSkin.of(context).accent : null,
      onPressed: _busy ? null : _toggle,
      tooltip:
          added ? l10n.readerRemoveFromBookshelf : l10n.readerAddToBookshelf,
    );
  }
}

String _shortDate(DateTime value) {
  final local = value.toLocal();
  String two(int part) => part.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)}';
}
