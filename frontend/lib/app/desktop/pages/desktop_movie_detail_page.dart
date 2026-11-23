import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omninest/app/desktop/desktop_backdrop_layer.dart';
import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_router_scope.dart';
import 'package:omninest/app/desktop/desktop_routes.dart';
import 'package:omninest/app/desktop/desktop_shell_state.dart';
import 'package:omninest/app/desktop/desktop_toast.dart';
import 'package:omninest/app/desktop/pages/desktop_movie_detail_actions.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_skeleton.dart';
import 'package:omninest/app/desktop/widgets/desktop_surfaces.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/utils/file_size_formatter.dart';
import 'package:omninest/core/utils/route_exit.dart';
import 'package:omninest/features/tasks/application/task_controller.dart';
import 'package:omninest/features/video/presentation/widgets/subtitle_file_decoder.dart';
import 'package:omninest/features/video/video_dashboard.dart';
import 'package:omninest/platform/file_pick.dart';

part 'desktop_movie_detail_hero.dart';
part 'desktop_movie_detail_sections.dart';
part 'desktop_movie_detail_subtitles.dart';

/// 桌面影视详情（样例 `FilmDetail`）。
///
/// 样例把详情页直接挂在 `.main` 里，因此这里是工作区内的普通内容页：
/// 标题栏、侧栏、坞和播放条全程在场，圆角英雄区只是页面第一块内容。
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
    final bgColor =
        desktopBackdropVisibleForRoute(
              ref,
              DesktopRoutes.movieDetail(widget.videoItemId),
            )
            ? Colors.transparent
            : skin.bg;
    final detail = ref.watch(movieDetailProvider(widget.videoItemId));
    final item = detail.asData?.value;
    if (item == null) {
      return ColoredBox(
        color: bgColor,
        child: Center(
          child:
              detail.hasError
                  ? Text(
                    failureToast(l10n, l10n.videoRedesignDetail, detail.error!),
                    style: DesktopType.body(skin.text3),
                  )
                  : const SizedBox(
                    width: 320,
                    child: DesktopSkeletonRows(count: 6, avatar: false),
                  ),
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
    ].take(5).toList(growable: false);

    return ColoredBox(
      color: bgColor,
      child: SingleChildScrollView(
        child: DesktopPage(
          // 样例 `.film-page { padding-top: 14px }` + `.fd-hero { margin: 6px 0 22px }`。
          topPadding: DesktopMetrics.pageTopPaddingCompact,
          children: [
            const SizedBox(height: 6),
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
            const SizedBox(height: 22),
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
                      _MovieDetailTab.overview => l10n.videoDetailTabOverview,
                      _MovieDetailTab.files => l10n.videoDetailTabFiles,
                      _MovieDetailTab.subtitles => l10n.desktopSeriesSubtitles,
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
              const SizedBox(height: 40),
              Text(
                l10n.desktopMoviesMoreLikeThis,
                style: DesktopType.sectionTitle(skin.text),
              ),
              const SizedBox(height: 18),
              _RelatedRail(items: related),
            ],
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
/// 数值按样例用 24px 衬线，缺值统一显示破折号，不摆空壳。
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
      (l10n.videoYear, year, _kindLabel(item, l10n)),
      (
        l10n.videoDuration,
        _formatRuntime(item.runtimeSeconds),
        l10n.desktopMoviesDetailDirectPlay,
      ),
      (
        l10n.videoGenre,
        item.genres.isEmpty ? '—' : item.genres.take(2).join(' · '),
        (item.contentRating ?? '').trim(),
      ),
      (
        l10n.desktopMoviesQuality,
        (item.resolutionHeight ?? 0) >= 2160
            ? '4K HDR'
            : (item.resolutionHeight ?? 0) >= 1080
            ? '1080p'
            : '—',
        (item.audioCodec ?? '').trim().toUpperCase(),
      ),
    ];
    return Container(
      decoration: BoxDecoration(
        color: skin.panel,
        borderRadius: BorderRadius.circular(16),
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
                      style: DesktopType.sectionTitle(
                        skin.text,
                      ).copyWith(letterSpacing: -24 * 0.01),
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
