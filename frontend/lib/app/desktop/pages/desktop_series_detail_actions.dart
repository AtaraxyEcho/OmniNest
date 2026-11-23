import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_router_scope.dart';
import 'package:omninest/app/desktop/desktop_routes.dart';
import 'package:omninest/app/desktop/desktop_toast.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_dialogs.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/features/video/domain/series_play_target.dart';
import 'package:omninest/features/video/video_dashboard.dart';

/// 系列级（TV / Anime）匹配候选弹窗：复用与电影页一致的候选卡片样式。
Future<void> showDesktopSeriesMatchDialog(
  BuildContext context,
  MovieSeries series,
) {
  return showDesktopDialog<void>(
    context,
    builder: (_) => _SeriesMatchCandidatesDialog(series: series),
  );
}

/// 触发系列级批量重新探测。
Future<void> runDesktopSeriesProbe(
  BuildContext context,
  WidgetRef ref,
  MovieSeries series,
) async {
  final l10n = AppLocalizations.of(context);
  try {
    await ref.read(movieApiProvider).probeSeries(series.id);
    if (!context.mounted) return;
    ref.invalidate(movieSeriesDetailProvider(series.id));
    ref.invalidate(movieSeriesEpisodesProvider(series.id));
    showDesktopToast(
      context,
      l10n.desktopMoviesProbeDone,
      kind: DesktopToastKind.success,
      icon: DesktopIcons.check,
    );
  } on Object catch (error) {
    if (!context.mounted) return;
    showDesktopToast(
      context,
      failureToast(l10n, l10n.desktopMoviesReprobe, error),
      kind: DesktopToastKind.error,
      icon: DesktopIcons.info,
    );
  }
}

/// 导出系列级 `tvshow.nfo`。
Future<void> runDesktopSeriesExportNfo(
  BuildContext context,
  WidgetRef ref,
  MovieSeries series,
) async {
  final l10n = AppLocalizations.of(context);
  try {
    final export = await ref.read(movieApiProvider).exportSeriesNfo(series.id);
    if (!context.mounted) return;
    ref.invalidate(movieSeriesDetailProvider(series.id));
    showDesktopToast(
      context,
      export.exportPath.isEmpty
          ? l10n.desktopMoviesNfoExported
          : '${l10n.desktopMoviesNfoExported} · ${export.exportPath}',
      kind: DesktopToastKind.success,
      icon: DesktopIcons.download,
    );
  } on Object catch (error) {
    if (!context.mounted) return;
    showDesktopToast(
      context,
      failureToast(l10n, l10n.desktopMoviesExportNfo, error),
      kind: DesktopToastKind.error,
      icon: DesktopIcons.info,
    );
  }
}

/// 单片卡片右键：重新探测。
Future<void> runDesktopMovieProbe(
  BuildContext context,
  WidgetRef ref,
  MovieVideoItem item,
) async {
  final l10n = AppLocalizations.of(context);
  try {
    await ref.read(movieDetailBackendActionsProvider).reprobe(item.id);
    if (!context.mounted) return;
    ref.invalidate(movieDetailProvider(item.id));
    showDesktopToast(
      context,
      l10n.desktopMoviesProbeDone,
      kind: DesktopToastKind.success,
      icon: DesktopIcons.check,
    );
  } on Object catch (error) {
    if (!context.mounted) return;
    showDesktopToast(
      context,
      failureToast(l10n, l10n.desktopMoviesReprobe, error),
      kind: DesktopToastKind.error,
      icon: DesktopIcons.info,
    );
  }
}

/// 单片卡片右键：导出 NFO。
Future<void> runDesktopMovieExportNfo(
  BuildContext context,
  WidgetRef ref,
  MovieVideoItem item,
) async {
  final l10n = AppLocalizations.of(context);
  try {
    final export = await ref
        .read(movieDetailBackendActionsProvider)
        .exportNfo(item.id);
    if (!context.mounted) return;
    ref.invalidate(movieDetailProvider(item.id));
    showDesktopToast(
      context,
      export.exportPath.isEmpty
          ? l10n.desktopMoviesNfoExported
          : '${l10n.desktopMoviesNfoExported} · ${export.exportPath}',
      kind: DesktopToastKind.success,
      icon: DesktopIcons.download,
    );
  } on Object catch (error) {
    if (!context.mounted) return;
    showDesktopToast(
      context,
      failureToast(l10n, l10n.desktopMoviesExportNfo, error),
      kind: DesktopToastKind.error,
      icon: DesktopIcons.info,
    );
  }
}

/// 系列卡片右键：按续播/下一集/首集意图立即播放。
Future<void> runDesktopSeriesPlay(
  BuildContext context,
  WidgetRef ref,
  MovieSeries series,
) async {
  final l10n = AppLocalizations.of(context);
  try {
    final intent = await ref.read(seriesPlayIntentProvider(series.id).future);
    if (!context.mounted) return;
    String? targetId = intent.videoItemId;
    if (intent.kind != SeriesPlayIntentKind.resume || targetId == null) {
      final episodes = await ref.read(
        movieSeriesEpisodesProvider(series.id).future,
      );
      if (!context.mounted) return;
      targetId = pickSeriesPlayEpisodeId(
        orderedEpisodes: sortEpisodesForPlay(episodes),
        afterVideoItemId:
            intent.kind == SeriesPlayIntentKind.nextEpisode
                ? intent.afterVideoItemId
                : null,
      );
    }
    if (targetId == null || targetId.isEmpty) {
      showDesktopToast(
        context,
        l10n.videoDetailNoPlayableEpisode,
        kind: DesktopToastKind.warn,
        icon: DesktopIcons.info,
      );
      return;
    }
    desktopPush(context, DesktopRoutes.moviePlay(targetId));
  } on Object catch (error) {
    if (!context.mounted) return;
    showDesktopToast(
      context,
      failureToast(l10n, l10n.videoPlay, error),
      kind: DesktopToastKind.error,
      icon: DesktopIcons.info,
    );
  }
}

/// 系列卡片右键：切换收藏状态。
Future<void> runDesktopSeriesToggleFavorite(
  BuildContext context,
  WidgetRef ref,
  MovieSeries series, {
  required bool currentFavorite,
}) async {
  final l10n = AppLocalizations.of(context);
  try {
    await ref
        .read(movieCenterControllerProvider.notifier)
        .setSeriesFavorite(series.id, favorite: !currentFavorite);
    if (!context.mounted) return;
    ref.invalidate(seriesFavoriteProvider(series.id));
    showDesktopToast(
      context,
      currentFavorite ? l10n.favoriteRemoved : l10n.favoriteAdded,
      kind: currentFavorite ? DesktopToastKind.info : DesktopToastKind.success,
      icon: currentFavorite ? DesktopIcons.heart : DesktopIcons.check,
    );
  } on Object catch (error) {
    if (!context.mounted) return;
    showDesktopToast(
      context,
      failureToast(l10n, l10n.videoFavorite, error),
      kind: DesktopToastKind.error,
      icon: DesktopIcons.info,
    );
  }
}

class _SeriesMatchCandidatesDialog extends ConsumerWidget {
  const _SeriesMatchCandidatesDialog({required this.series});

  final MovieSeries series;

  Future<void> _apply(
    BuildContext context,
    WidgetRef ref,
    VideoScrapeCandidate candidate,
  ) async {
    final l10n = AppLocalizations.of(context);
    try {
      await ref
          .read(movieApiProvider)
          .createSeriesScrapeTask(
            seriesId: series.id,
            force: true,
            provider: candidate.provider,
            externalId: candidate.externalId,
          );
      if (!context.mounted) return;
      ref.invalidate(seriesScrapeCandidatesProvider(series.id));
      ref.invalidate(movieSeriesDetailProvider(series.id));
      showDesktopToast(
        context,
        l10n.desktopMoviesMatchQueued,
        icon: DesktopIcons.sparkle,
      );
      closeDesktopModal(context);
    } on Object catch (error) {
      if (context.mounted) {
        showDesktopToast(
          context,
          failureToast(l10n, l10n.desktopMoviesMatchMetadata, error),
          kind: DesktopToastKind.error,
          icon: DesktopIcons.info,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final candidates = ref.watch(seriesScrapeCandidatesProvider(series.id));
    return DesktopDialog(
      eyebrow: l10n.desktopMoviesMatchMetadata,
      title: l10n.desktopMoviesMatchTitle,
      width: 560,
      content: candidates.when(
        loading:
            () => Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text(
                l10n.desktopMoviesMatchLoading,
                style: DesktopType.body(skin.text3),
              ),
            ),
        error:
            (error, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                failureToast(l10n, l10n.desktopMoviesMatchMetadata, error),
                style: DesktopType.body(skin.text3),
              ),
            ),
        data: (items) {
          if (items.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text(
                l10n.desktopMoviesMatchEmpty,
                style: DesktopType.body(skin.text3),
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final candidate in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _SeriesCandidateRow(
                    candidate: candidate,
                    onTap: () => unawaited(_apply(context, ref, candidate)),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SeriesCandidateRow extends StatelessWidget {
  const _SeriesCandidateRow({required this.candidate, required this.onTap});

  final VideoScrapeCandidate candidate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final subtitle = [
      if (candidate.year != null) '${candidate.year}',
      if (candidate.provider.isNotEmpty) candidate.provider,
      if (candidate.externalId.isNotEmpty) '#${candidate.externalId}',
    ].join(' · ');
    return DesktopHover(
      builder:
          (context, hovered) => GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: DesktopMotion.fast,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: hovered ? skin.raise2 : skin.raise,
                borderRadius: BorderRadius.circular(DesktopMetrics.radiusSmall),
                border: Border.all(color: skin.line),
              ),
              child: Row(
                children: [
                  Icon(DesktopIcons.film, size: 16, color: skin.text3),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          candidate.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DesktopType.rowTitle(skin.text),
                        ),
                        if (subtitle.isNotEmpty)
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DesktopType.caption(skin.text3),
                          ),
                      ],
                    ),
                  ),
                  if (candidate.voteAverage != null) ...[
                    const SizedBox(width: 8),
                    DesktopChip(
                      candidate.voteAverage!.toStringAsFixed(1),
                      tone: skin.warm,
                    ),
                  ],
                ],
              ),
            ),
          ),
    );
  }
}

/// 剧集/番剧概览页动作行：编辑详情 / 匹配元数据 / 重新探测 / 导出 NFO。
class DesktopSeriesOverviewActions extends ConsumerStatefulWidget {
  const DesktopSeriesOverviewActions({
    required this.series,
    required this.onEdit,
    super.key,
  });

  final MovieSeries series;
  final VoidCallback onEdit;

  @override
  ConsumerState<DesktopSeriesOverviewActions> createState() =>
      _DesktopSeriesOverviewActionsState();
}

class _DesktopSeriesOverviewActionsState
    extends ConsumerState<DesktopSeriesOverviewActions> {
  bool _probing = false;
  bool _exporting = false;

  bool get _scraped {
    final status = widget.series.metadataStatus.toUpperCase();
    return status == 'MATCHED' || status == 'MANUAL';
  }

  Future<void> _probe() async {
    setState(() => _probing = true);
    try {
      await runDesktopSeriesProbe(context, ref, widget.series);
    } finally {
      if (mounted) setState(() => _probing = false);
    }
  }

  Future<void> _exportNfo() async {
    setState(() => _exporting = true);
    try {
      await runDesktopSeriesExportNfo(context, ref, widget.series);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        DesktopButton(
          label: l10n.desktopMoviesEditDetails,
          icon: DesktopIcons.edit,
          variant: DesktopButtonVariant.soft,
          onPressed: widget.onEdit,
        ),
        DesktopButton(
          label:
              _scraped
                  ? l10n.desktopMoviesRematchMetadata
                  : l10n.desktopMoviesMatchMetadata,
          icon: DesktopIcons.sparkle,
          variant: DesktopButtonVariant.soft,
          onPressed:
              () => unawaited(
                showDesktopSeriesMatchDialog(context, widget.series),
              ),
        ),
        DesktopButton(
          label: l10n.desktopMoviesReprobe,
          icon: DesktopIcons.retry,
          variant: DesktopButtonVariant.soft,
          busy: _probing,
          onPressed: _probing ? null : () => unawaited(_probe()),
        ),
        DesktopButton(
          label: l10n.desktopMoviesExportNfo,
          icon: DesktopIcons.download,
          variant: DesktopButtonVariant.soft,
          busy: _exporting,
          onPressed: _exporting ? null : () => unawaited(_exportNfo()),
        ),
      ],
    );
  }
}
