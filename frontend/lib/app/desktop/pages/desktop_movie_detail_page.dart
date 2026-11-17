import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_router_scope.dart';
import 'package:omninest/app/desktop/desktop_routes.dart';
import 'package:omninest/app/desktop/desktop_shell_state.dart';
import 'package:omninest/app/desktop/desktop_toast.dart';
import 'package:omninest/app/desktop/pages/desktop_movie_detail_actions.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_surfaces.dart';
import 'package:omninest/app/desktop/widgets/desktop_tilt.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/utils/file_size_formatter.dart';
import 'package:omninest/core/utils/route_exit.dart';
import 'package:omninest/features/tasks/application/task_controller.dart';
import 'package:omninest/features/video/video_dashboard.dart';

part 'desktop_movie_detail_sections.dart';

/// 桌面影视详情（样例 `FilmDetail`）。
///
/// 满铺英雄区（剧照 + 海报 + 文案与动作）+ 概览/字幕分页 + 相关推荐。
/// 数据走模块门面：详情、观看历史、字幕、收藏状态各一个 provider；
/// 播放仍跳既有播放路由，播放器覆盖层另批处理。
class DesktopMovieDetailPage extends ConsumerStatefulWidget {
  const DesktopMovieDetailPage({required this.videoItemId, super.key});

  final String videoItemId;

  @override
  ConsumerState<DesktopMovieDetailPage> createState() =>
      _DesktopMovieDetailPageState();
}

class _DesktopMovieDetailPageState
    extends ConsumerState<DesktopMovieDetailPage> {
  _MovieDetailTab _tab = _MovieDetailTab.overview;
  bool _savingFavorite = false;
  bool _transcoding = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final detail = ref.watch(movieDetailProvider(widget.videoItemId));
    final item = detail.asData?.value;
    if (item == null) {
      return ColoredBox(
        color: skin.bg,
        child: Center(
          child:
              detail.hasError
                  ? Text(
                    failureToast(l10n, l10n.videoRedesignDetail, detail.error!),
                    style: DesktopType.body(skin.text3),
                  )
                  : const SizedBox(width: 28, height: 28),
        ),
      );
    }
    final history =
        ref.watch(movieItemHistoryProvider(widget.videoItemId)).asData?.value;
    final favorite =
        ref
            .watch(videoFavoriteStatusProvider(widget.videoItemId))
            .asData
            ?.value ??
        false;
    final watched = history?.completed ?? false;
    final watchlistItems = ref.watch(movieWatchlistProvider);
    final watchlisted = watchlistItems.any(
      (candidate) => candidate.id == item.id,
    );
    final engagementState = ref.watch(movieDetailActionProvider);
    final dashboard = ref.watch(movieDashboardProvider).asData?.value;
    final related = <MovieVideoItem>[
      for (final candidate in [
        ...?dashboard?.recentlyAdded,
        ...?dashboard?.continueWatching.map(_resumeAsItem),
      ])
        if (candidate.id != item.id &&
            (candidate.genres.any(item.genres.contains) ||
                candidate.mediaType == item.mediaType))
          candidate,
    ].take(8).toList(growable: false);

    return ColoredBox(
      color: skin.bg,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Hero(
              item: item,
              history: history,
              favorite: favorite,
              watched: watched,
              watchlisted: watchlisted,
              saving: _savingFavorite,
              engaging: engagementState.engaging,
              onBack: () => exitDetailRoute(context, fallbackRoute: '/video'),
              onPlay:
                  () => desktopPush(context, DesktopRoutes.moviePlay(item.id)),
              onFromStart:
                  () => desktopPush(
                    context,
                    DesktopRoutes.moviePlay(item.id, fromStart: true),
                  ),
              onToggleFavorite: () => _toggleFavorite(item, favorite),
              onToggleWatched: () => _toggleWatched(item, history),
              onToggleWatchlist: () => _toggleWatchlist(item),
            ),
            DesktopPage(
              topPadding: 22,
              children: [
                _MetaStrip(item: item),
                const SizedBox(height: 22),
                Align(
                  alignment: Alignment.centerLeft,
                  child: DesktopSeg<_MovieDetailTab>(
                    options: _MovieDetailTab.values,
                    value: _tab,
                    onChanged: (value) => setState(() => _tab = value),
                    labelOf:
                        (value) => switch (value) {
                          _MovieDetailTab.overview =>
                            l10n.videoDetailTabOverview,
                          _MovieDetailTab.files => l10n.videoDetailTabFiles,
                          _MovieDetailTab.subtitles =>
                            l10n.desktopSeriesSubtitles,
                        },
                    small: true,
                  ),
                ),
                const SizedBox(height: 20),
                switch (_tab) {
                  _MovieDetailTab.overview => _Overview(item: item),
                  _MovieDetailTab.files => _MovieFilesTab(
                    videoItemId: item.id,
                    transcoding: _transcoding,
                    onTranscode: () => _queueTranscode(item),
                  ),
                  _MovieDetailTab.subtitles => _Subtitles(videoItemId: item.id),
                },
                if (related.isNotEmpty) ...[
                  const SizedBox(height: 36),
                  Text(
                    l10n.desktopMoviesMoreLikeThis.toUpperCase(),
                    style: DesktopType.eyebrow(skin.text3),
                  ),
                  const SizedBox(height: 14),
                  _RelatedRail(items: related),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleFavorite(MovieVideoItem item, bool favorite) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _savingFavorite = true);
    try {
      await ref
          .read(movieCenterControllerProvider.notifier)
          .toggleFavorite(item, favorite: !favorite);
      if (!mounted) {
        return;
      }
      ref.invalidate(videoFavoriteStatusProvider(item.id));
      showDesktopToast(
        context,
        favorite ? l10n.favoriteRemoved : l10n.favoriteAdded,
        kind: favorite ? DesktopToastKind.info : DesktopToastKind.success,
        icon: DesktopIcons.heart,
      );
    } on Object catch (error) {
      if (mounted) {
        showDesktopToast(
          context,
          failureToast(l10n, l10n.videoFavorite, error),
          kind: DesktopToastKind.error,
          icon: DesktopIcons.info,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _savingFavorite = false);
      }
    }
  }

  Future<void> _toggleWatched(
    MovieVideoItem item,
    MovieWatchHistory? history,
  ) async {
    final l10n = AppLocalizations.of(context);
    final watched = history?.completed ?? false;
    final historyDuration = history?.durationSeconds ?? 0;
    final durationSeconds =
        historyDuration > 0 ? historyDuration : (item.runtimeSeconds ?? 0);
    try {
      final completed = await ref
          .read(movieDetailActionProvider.notifier)
          .engage(
            () => ref
                .read(movieEngagementActionsProvider)
                .setWatched(
                  videoItemId: item.id,
                  watched: !watched,
                  durationSeconds: durationSeconds,
                ),
          );
      if (!mounted || !completed) {
        return;
      }
      ref.invalidate(movieItemHistoryProvider(item.id));
      ref.invalidate(movieDashboardProvider);
      ref.invalidate(movieCenterControllerProvider);
      showDesktopToast(
        context,
        watched
            ? l10n.desktopMoviesMarkedUnwatched(item.title)
            : l10n.desktopMoviesMarkedWatched(item.title),
        kind: DesktopToastKind.success,
        icon: DesktopIcons.check,
      );
    } on Object catch (error) {
      if (mounted) {
        showDesktopToast(
          context,
          failureToast(l10n, l10n.videoWatched, error),
          kind: DesktopToastKind.error,
          icon: DesktopIcons.info,
        );
      }
    }
  }

  Future<void> _toggleWatchlist(MovieVideoItem item) async {
    final l10n = AppLocalizations.of(context);
    bool? added;
    try {
      final completed = await ref
          .read(movieDetailActionProvider.notifier)
          .engage(() async {
            added = await ref
                .read(movieWatchlistProvider.notifier)
                .toggle(item);
          });
      if (!mounted || !completed || added == null) {
        return;
      }
      showDesktopToast(
        context,
        added!
            ? l10n.desktopMoviesAddedWatchlist
            : l10n.desktopMoviesRemovedWatchlist,
        kind: added! ? DesktopToastKind.success : DesktopToastKind.info,
        icon: added! ? DesktopIcons.check : DesktopIcons.trash,
      );
    } on Object catch (error) {
      if (mounted) {
        showDesktopToast(
          context,
          failureToast(l10n, l10n.desktopMoviesWatchlist, error),
          kind: DesktopToastKind.error,
          icon: DesktopIcons.info,
        );
      }
    }
  }

  Future<void> _queueTranscode(MovieVideoItem item) async {
    if (_transcoding) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _transcoding = true);
    try {
      await ref.read(movieApiProvider).createTranscodeTask(item.id);
      if (!mounted) return;
      ref.invalidate(movieItemFilesProvider(item.id));
      ref.invalidate(activeTaskSummaryProvider);
      final container = ProviderScope.containerOf(context, listen: false);
      showDesktopToast(
        context,
        l10n.desktopMoviesTranscodeQueued,
        kind: DesktopToastKind.success,
        icon: DesktopIcons.check,
        actionLabel: l10n.desktopBackgroundTasks,
        onAction:
            () => container
                .read(desktopShellProvider.notifier)
                .setPanel(DesktopPanel.tasks),
      );
    } on Object catch (error) {
      if (mounted) {
        showDesktopToast(
          context,
          failureToast(l10n, l10n.videoTranscode, error),
          kind: DesktopToastKind.error,
          icon: DesktopIcons.info,
        );
      }
    } finally {
      if (mounted) setState(() => _transcoding = false);
    }
  }
}

MovieVideoItem _resumeAsItem(MovieContinueWatching entry) => MovieVideoItem(
  id: entry.id,
  fileNodeId: '',
  mediaType: entry.mediaType ?? '',
  title: entry.title,
  metadataStatus: '',
  nfoStatus: '',
  updatedAt: null,
  metadata: const {},
  posterUrl: entry.posterUrl,
);

/// 五格统计条（样例 `.fd-strip`）：评分 / 年份 / 时长 / 题材 / 音轨。
/// 只在有值的格子给 hint，缺值统一显示破折号，不摆空壳。
class _MetaStrip extends StatelessWidget {
  const _MetaStrip({required this.item});

  final MovieVideoItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final year = item.releaseDate?.year.toString() ?? '—';
    final cells = <(String, String, String)>[
      (l10n.videoRating, item.rating?.toStringAsFixed(1) ?? '—', 'TMDB'),
      (l10n.videoYear, year, item.mediaType),
      (
        l10n.videoDuration,
        _formatRuntime(item.runtimeSeconds),
        item.contentRating ?? '',
      ),
      (
        l10n.videoGenre,
        item.genres.isEmpty ? '—' : item.genres.take(2).join(' · '),
        '',
      ),
      (
        l10n.videoAudio,
        (item.audioCodec ?? '—').toUpperCase(),
        item.containerFormat?.toUpperCase() ?? '',
      ),
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

class _Hero extends StatelessWidget {
  const _Hero({
    required this.item,
    required this.history,
    required this.favorite,
    required this.watched,
    required this.watchlisted,
    required this.saving,
    required this.engaging,
    required this.onBack,
    required this.onPlay,
    required this.onFromStart,
    required this.onToggleFavorite,
    required this.onToggleWatched,
    required this.onToggleWatchlist,
  });

  final MovieVideoItem item;
  final MovieWatchHistory? history;
  final bool favorite;
  final bool watched;
  final bool watchlisted;
  final bool saving;
  final bool engaging;
  final VoidCallback onBack;
  final VoidCallback onPlay;
  final VoidCallback onFromStart;
  final VoidCallback onToggleFavorite;
  final VoidCallback onToggleWatched;
  final VoidCallback onToggleWatchlist;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final progress = watched ? 0.0 : _progress(history);
    final resumeLabel =
        progress > 0.02 && progress < 0.98
            ? l10n.videoHeroResume
            : l10n.videoPlay;
    final horizontal = (MediaQuery.sizeOf(context).width * 0.03).clamp(
      DesktopMetrics.pageHorizontalMin,
      DesktopMetrics.pageHorizontalMax,
    );
    // 样例 `.fd-hero { height: clamp(360px, 48vh, 500px) }`。
    final heroHeight = (MediaQuery.sizeOf(context).height * 0.48).clamp(
      360.0,
      500.0,
    );
    return SizedBox(
      height: heroHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DesktopImage(url: item.backdropUrl ?? item.posterUrl),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  skin.bg.withValues(alpha: 0.45),
                  skin.bg.withValues(alpha: 0.12),
                  skin.bg,
                ],
                stops: const [0, 0.52, 1],
              ),
            ),
          ),
          Positioned.fill(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: DesktopMetrics.pageMaxWidth,
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(horizontal, 18, horizontal, 26),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          DesktopButton(
                            label: l10n.desktopNavMovies,
                            icon: DesktopIcons.left,
                            variant: DesktopButtonVariant.glass,
                            onPressed: onBack,
                          ),
                        ],
                      ),
                      const Spacer(),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          SizedBox(
                            width: 184,
                            child: AspectRatio(
                              aspectRatio: 2 / 3,
                              child: DesktopTilt(
                                child: DesktopImage(
                                  url: item.posterUrl,
                                  borderRadius: BorderRadius.circular(
                                    DesktopMetrics.radiusCard,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 26),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    if (item.mediaType.isNotEmpty)
                                      DesktopChip(item.mediaType, solid: true),
                                    for (final genre in item.genres.take(2))
                                      DesktopChip(genre),
                                    if (item.rating != null)
                                      DesktopChip(
                                        '★ ${item.rating!.toStringAsFixed(1)}',
                                        tone: skin.warm,
                                      ),
                                    if (watched) DesktopChip(l10n.videoWatched),
                                    if (_notScraped(item))
                                      DesktopChip(
                                        l10n.desktopMoviesNotScraped,
                                        tone: skin.warn,
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  item.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: DesktopType.displayXl(
                                    skin.text,
                                    MediaQuery.sizeOf(context).width,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  [
                                        _formatRuntime(item.runtimeSeconds),
                                        if (item.metadata['year'] != null)
                                          '${item.metadata['year']}',
                                        if (item.genres.isNotEmpty)
                                          item.genres.first,
                                      ]
                                      .where((part) => part.isNotEmpty)
                                      .join(' · '),
                                  style: DesktopType.caption(skin.text3),
                                ),
                                if (progress > 0.02) ...[
                                  const SizedBox(height: 14),
                                  SizedBox(
                                    width: 420,
                                    child: DesktopProgress(
                                      fraction: progress,
                                      label: l10n.desktopMoviesWatched(
                                        (progress * 100).round(),
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 18),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    DesktopButton(
                                      label: resumeLabel,
                                      icon: DesktopIcons.play,
                                      variant: DesktopButtonVariant.primary,
                                      large: true,
                                      onPressed: onPlay,
                                    ),
                                    if (progress > 0.02) ...[
                                      DesktopButton(
                                        label: l10n.desktopMoviesFromStart,
                                        variant: DesktopButtonVariant.glass,
                                        large: true,
                                        onPressed: onFromStart,
                                      ),
                                    ],
                                    DesktopButton.iconOnly(
                                      icon:
                                          favorite
                                              ? DesktopIcons.heartFilled
                                              : DesktopIcons.heart,
                                      variant: DesktopButtonVariant.glass,
                                      large: true,
                                      foregroundOverride:
                                          favorite ? skin.liked : null,
                                      tooltip: l10n.videoFavorite,
                                      onPressed:
                                          saving ? null : onToggleFavorite,
                                    ),
                                    DesktopButton.iconOnly(
                                      icon: DesktopIcons.check,
                                      variant: DesktopButtonVariant.glass,
                                      large: true,
                                      tooltip:
                                          watched
                                              ? l10n.desktopMoviesMarkUnwatched
                                              : l10n.desktopMoviesMarkWatched,
                                      onPressed:
                                          engaging ? null : onToggleWatched,
                                    ),
                                    DesktopButton.iconOnly(
                                      icon:
                                          watchlisted
                                              ? DesktopIcons.check
                                              : DesktopIcons.plus,
                                      variant: DesktopButtonVariant.glass,
                                      large: true,
                                      tooltip:
                                          watchlisted
                                              ? l10n
                                                  .desktopMoviesRemoveWatchlist
                                              : l10n.desktopMoviesAddWatchlist,
                                      onPressed:
                                          engaging ? null : onToggleWatchlist,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

double _progress(MovieWatchHistory? history) {
  if (history == null || history.durationSeconds <= 0) {
    return 0;
  }
  return (history.positionSeconds / history.durationSeconds).clamp(0.0, 1.0);
}

String _formatRuntime(int? seconds) {
  if (seconds == null || seconds <= 0) {
    return '—';
  }
  final duration = Duration(seconds: seconds);
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  return hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
}

/// 样例 `scraped=false` 的徽章口径：只有已匹配或手动维护过的条目算已完成刮削。
bool _notScraped(MovieVideoItem item) {
  final status = item.metadataStatus.toUpperCase();
  return status.isEmpty || status == 'PENDING' || status == 'FAILED';
}
