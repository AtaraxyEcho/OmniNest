import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omninest/app/desktop/desktop_backdrop_layer.dart';
import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_routes.dart';
import 'package:omninest/app/desktop/desktop_router_scope.dart';
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
          final tone = Color.lerp(skin.panelSolid, skin.accent, 0.24)!;

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: DesktopLink(
                      label: l10n.desktopReaderLibrary,
                      icon: DesktopIcons.left,
                      trailing: false,
                      onPressed:
                          () => exitDetailRoute(
                            context,
                            fallbackRoute: '/reader',
                          ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    // 样例 `.bp-hero { padding: 36px 44px }`。
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
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // 样例 `.bp-cover`：静止 -14deg，hover 收到 -4deg。
                        DesktopBookTilt(
                          child: _BookCover(item: item, large: true),
                        ),
                        const SizedBox(width: 44),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  DesktopChip(
                                    '${item.itemType} · ${item.contentKind}',
                                    solid: true,
                                  ),
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
                              if (hasProgress) ...[
                                const SizedBox(height: 18),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 420,
                                  ),
                                  child: _ProgressBar(value: percent / 100),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  l10n.readerChapterPosition(
                                    (currentIndex < 0 ? 0 : currentIndex) + 1,
                                    chapters.length,
                                  ),
                                  style: DesktopType.caption(skin.text3),
                                ),
                              ],
                              const SizedBox(height: 22),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
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
                                        chapters.isEmpty
                                            ? null
                                            : () => _openChapter(
                                              context,
                                              itemId,
                                              chapters,
                                              progress,
                                              resume: hasProgress,
                                            ),
                                  ),
                                  if (hasProgress)
                                    DesktopButton(
                                      label: l10n.readerStartReading,
                                      variant: DesktopButtonVariant.glass,
                                      large: true,
                                      onPressed:
                                          chapters.isEmpty
                                              ? null
                                              : () => _openChapter(
                                                context,
                                                itemId,
                                                chapters,
                                                null,
                                                resume: false,
                                              ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                DesktopPage(
                  topPadding: 24,
                  children: [
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
                          (chapter) => _openChapter(
                            context,
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
              ],
            ),
          );
        },
      ),
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
    final skin = DesktopSkin.of(context);
    return SizedBox(
      width: large ? 200 : 120,
      height: large ? 300 : 180,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(skin.accent, skin.panelSolid, 0.45)!,
              skin.panelSolid,
            ],
          ),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(10),
            bottomRight: Radius.circular(10),
            bottomLeft: Radius.circular(4),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 30,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(10),
            bottomRight: Radius.circular(10),
            bottomLeft: Radius.circular(4),
          ),
          child:
              item.coverUrl?.isNotEmpty == true
                  ? DesktopImage(url: item.coverUrl)
                  : Stack(
                    children: [
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: 12,
                        child: ColoredBox(
                          color: Colors.black.withValues(alpha: 0.28),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 18, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              item.title,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: DesktopType.displaySm(skin.onStage),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              item.authorName ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DesktopType.caption(
                                skin.onStageWash(0.75),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
        ),
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
    final cells = <(String, String, String)>[
      (
        l10n.desktopBookProgress,
        '${percent.round()}%',
        l10n.readerChapterPosition(
          (currentIndex < 0 ? 0 : currentIndex) + 1,
          chapters,
        ),
      ),
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

String _shortDate(DateTime value) {
  final local = value.toLocal();
  String two(int part) => part.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)}';
}
