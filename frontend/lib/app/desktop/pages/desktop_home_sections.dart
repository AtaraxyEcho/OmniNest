import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_router_scope.dart';
import 'package:omninest/app/desktop/desktop_routes.dart';
import 'package:omninest/app/desktop/desktop_shell_state.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_cover.dart';
import 'package:omninest/app/desktop/widgets/desktop_error_view.dart';
import 'package:omninest/app/desktop/widgets/desktop_skeleton.dart';
import 'package:omninest/app/desktop/widgets/desktop_surfaces.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_palette.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/features/music/music_portal.dart';
import 'package:omninest/features/reader/reader_dashboard.dart';
import 'package:omninest/features/video/video_dashboard.dart';

part 'desktop_home_reading_card.dart';

/// 继续观看轨道（样例 `.rail` + `.wide-card`）。
class DesktopContinueRail extends ConsumerWidget {
  const DesktopContinueRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final dashboardAsync = ref.watch(movieDashboardProvider);
    final dashboard = dashboardAsync.asData?.value;
    if (dashboard == null && dashboardAsync.hasError) {
      return DesktopErrorView(
        message: errorReason(dashboardAsync.error!, l10n),
        onRetry: () => ref.invalidate(movieDashboardProvider),
        minHeightFactor: 0.22,
      );
    }
    final skeleton = SizedBox(
      height: 340 * 9 / 16 + 16,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 12, top: 4),
        itemCount: 4,
        separatorBuilder:
            (context, index) => const SizedBox(width: DesktopMetrics.railGap),
        itemBuilder:
            (context, index) => SizedBox(
              width: 340,
              child: DesktopSkeletonBox(height: 191, radius: 16, index: index),
            ),
      ),
    );
    final seenResume = <String>{};
    final resumeIds = <String>{};
    final resumeSeries = <String>{};
    final resumeMovies = <String>{};
    final resume = <MovieContinueWatching>[];
    for (final item
        in dashboard?.continueWatching ?? const <MovieContinueWatching>[]) {
      if (item.title.trim().isEmpty) continue;
      final sid = item.seriesId?.trim();
      final mid = item.movieId?.trim();
      final key =
          (sid != null && sid.isNotEmpty)
              ? 's:$sid'
              : (mid != null && mid.isNotEmpty)
              ? 'm:$mid'
              : 'v:${item.id}';
      if (!seenResume.add(key)) continue;
      resume.add(item);
      resumeIds.add(item.id);
      if (sid != null && sid.isNotEmpty) resumeSeries.add(sid);
      if (mid != null && mid.isNotEmpty) resumeMovies.add(mid);
    }
    final seenFresh = <String>{};
    final fresh = <MovieVideoItem>[];
    for (final item in dashboard?.recentlyAdded ?? const <MovieVideoItem>[]) {
      final status = item.metadataStatus.toUpperCase();
      if (status == 'FAILED' ||
          status == 'PENDING' ||
          item.title.trim().isEmpty) {
        continue;
      }
      final sid = item.seriesId?.trim();
      final mid = item.movieId?.trim();
      if (resumeIds.contains(item.id) ||
          (sid != null && resumeSeries.contains(sid)) ||
          (mid != null && resumeMovies.contains(mid))) {
        continue;
      }
      final key =
          (sid != null && sid.isNotEmpty)
              ? 's:$sid'
              : (mid != null && mid.isNotEmpty)
              ? 'm:$mid'
              : 'v:${item.id}';
      if (!seenFresh.add(key)) continue;
      fresh.add(item);
    }
    final Widget content;
    if (resume.isEmpty && fresh.isEmpty) {
      content = DesktopEmpty(
        message: l10n.desktopHomeEmptyContinue,
        icon: DesktopIcons.film,
        actionLabel: l10n.desktopAllMovies,
        onAction: () => context.go(DesktopRoutes.movies),
      );
    } else {
      final freshItems = fresh
          .take(math.max(0, 4 - resume.length))
          .toList(growable: false);
      // 样例 `.rail > *`：每张卡按 `--i * 55ms` 各自入场，不是整条轨道一起淡入。
      final entries = <Widget>[
        for (var i = 0; i < resume.length; i++)
          DesktopStagger(index: i, child: _ResumeCard(item: resume[i])),
        for (var i = 0; i < freshItems.length; i++)
          DesktopStagger(
            index: resume.length + i,
            child: _FreshCard(item: freshItems[i]),
          ),
      ];
      // 样例 `.wide-card`：`width:340 + aspect-ratio:16/9` → 191.25 高，
      // 加上下留白 16 就是轨道高度。写死 214 会让卡片比设计稿高 22.75。
      content = SizedBox(
        height: 340 * 9 / 16 + 16,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(bottom: 12, top: 4),
          itemCount: entries.length,
          separatorBuilder:
              (context, index) => const SizedBox(width: DesktopMetrics.railGap),
          itemBuilder: (context, index) => entries[index],
        ),
      );
    }
    return DesktopSkeletonSwitcher(
      regionId: 'home-continue-rail',
      hasData: dashboard != null,
      loading: dashboard == null && dashboardAsync.isLoading,
      skeleton: skeleton,
      child: content,
    );
  }
}

class _ResumeCard extends ConsumerWidget {
  const _ResumeCard({required this.item});

  final MovieContinueWatching item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final remaining = (100 - item.progressPercent).round().clamp(0, 100);
    void showQuickLook() {
      ref
          .read(desktopShellProvider.notifier)
          .showDetail(
            DesktopDetailData(
              id: 'film:${item.id}',
              kind: 'film',
              title: item.title,
              subtitle: item.mediaType ?? '',
              imageUrl: item.posterUrl,
              progress: item.progressPercent / 100,
              factsLabel: l10n.desktopOpenDetails,
              primary: DesktopDetailAction(
                label: l10n.desktopPlay,
                icon: DesktopIcons.play,
                onPressed:
                    (ctx, r) =>
                        desktopPush(ctx, DesktopRoutes.moviePlay(item.id)),
              ),
              secondary: DesktopDetailAction(
                label: l10n.desktopOpenDetails,
                icon: DesktopIcons.info,
                onPressed:
                    (ctx, r) =>
                        desktopPush(ctx, DesktopRoutes.movieDetail(item.id)),
              ),
            ),
          );
    }

    return _WideCard(
      imageUrl: item.posterUrl,
      title: item.title,
      caption: l10n.desktopPercentLeft(remaining),
      progress: item.progressPercent / 100,
      onTap: () => context.push(DesktopRoutes.movieDetail(item.id)),
      onPlay: () => context.push(DesktopRoutes.moviePlay(item.id)),
      onSecondaryTapDown:
          (details) => _openFilmMenu(
            context,
            ref,
            l10n,
            item.id,
            details.globalPosition,
            showQuickLook,
          ),
      playLabel: l10n.desktopPlayTitle(item.title),
      surface: skin,
    );
  }
}

class _FreshCard extends ConsumerWidget {
  const _FreshCard({required this.item});

  final MovieVideoItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final rawYear =
        item.releaseDate?.year.toString() ??
        item.metadata['year']?.toString().trim() ??
        '';
    final hasYear =
        item.metadataStatus.toUpperCase() != 'PENDING' && rawYear.isNotEmpty;
    final yearText = hasYear ? rawYear : '';
    final genresShort = item.genres.take(2).join(' / ');
    final captionParts = <String>[
      if (hasYear) yearText,
      if (genresShort.isNotEmpty) genresShort,
    ];
    final genresFull = item.genres.join(' / ');
    final runtimeText = item.runtimeText.trim();
    final subtitleParts = <String>[
      if (hasYear) yearText,
      if (runtimeText.isNotEmpty) runtimeText,
      if (genresFull.isNotEmpty) genresFull,
    ];
    void showQuickLook() {
      ref
          .read(desktopShellProvider.notifier)
          .showDetail(
            DesktopDetailData(
              id: 'film:${item.id}',
              kind: 'film',
              title: item.title,
              subtitle: subtitleParts.join(' · '),
              imageUrl: item.backdropImageUrl ?? item.posterImageUrl,
              badge:
                  item.rating != null
                      ? '★ ${item.rating!.toStringAsFixed(1)}'
                      : null,
              about: item.overview,
              chips: item.castMembers.map((e) => e.name).take(8).toList(),
              factsLabel: l10n.desktopOpenDetails,
              primary: DesktopDetailAction(
                label: l10n.desktopPlay,
                icon: DesktopIcons.play,
                onPressed:
                    (ctx, r) =>
                        desktopPush(ctx, DesktopRoutes.moviePlay(item.id)),
              ),
              secondary: DesktopDetailAction(
                label: l10n.desktopOpenDetails,
                icon: DesktopIcons.info,
                onPressed:
                    (ctx, r) =>
                        desktopPush(ctx, DesktopRoutes.movieDetail(item.id)),
              ),
            ),
          );
    }

    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    return _WideCard(
      imageUrl: item.backdropImageUrl ?? item.posterImageUrl,
      title: item.title,
      caption: captionParts.join(' · '),
      badge: isZh ? '新入库' : 'New',
      onTap: () => context.push(DesktopRoutes.movieDetail(item.id)),
      onPlay: () => context.push(DesktopRoutes.moviePlay(item.id)),
      onSecondaryTapDown:
          (details) => _openFilmMenu(
            context,
            ref,
            l10n,
            item.id,
            details.globalPosition,
            showQuickLook,
          ),
      playLabel: l10n.desktopPlayTitle(item.title),
      surface: DesktopSkin.of(context),
    );
  }
}

void _openFilmMenu(
  BuildContext context,
  WidgetRef ref,
  AppLocalizations l10n,
  String videoId,
  Offset position,
  VoidCallback showQuickLook,
) {
  ref.read(desktopShellProvider.notifier).openMenu(position, [
    DesktopMenuItem(
      label: l10n.desktopPlay,
      icon: DesktopIcons.play,
      onPressed: () => desktopPush(context, DesktopRoutes.moviePlay(videoId)),
    ),
    DesktopMenuItem(
      label: l10n.desktopQuickLook,
      icon: DesktopIcons.panel,
      onPressed: showQuickLook,
    ),
    DesktopMenuItem(
      label: l10n.desktopOpenDetails,
      icon: DesktopIcons.info,
      onPressed: () => desktopPush(context, DesktopRoutes.movieDetail(videoId)),
    ),
  ]);
}

class _WideCard extends StatelessWidget {
  const _WideCard({
    required this.imageUrl,
    required this.title,
    required this.caption,
    required this.onTap,
    required this.onPlay,
    required this.onSecondaryTapDown,
    required this.playLabel,
    required this.surface,
    this.progress,
    this.badge,
  });

  final String? imageUrl, badge;
  final String title, caption, playLabel;
  final VoidCallback onTap, onPlay;
  final GestureTapDownCallback onSecondaryTapDown;
  final DesktopSkin surface;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(16);
    return SizedBox(
      width: 340,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: DesktopHover(
          builder:
              (context, hovered) => GestureDetector(
                onTap: onTap,
                onSecondaryTapDown: onSecondaryTapDown,
                behavior: HitTestBehavior.opaque,
                child: AnimatedScale(
                  duration: MotionToken.reduced(context, MotionToken.normal),
                  curve: MotionToken.curve,
                  scale: hovered ? 1.015 : 1,
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: radius,
                      boxShadow: hovered ? surface.shadow : null,
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        DesktopCover(
                          url: imageUrl,
                          fallbackIcon: DesktopIcons.film,
                          iconSize: 32,
                        ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black87],
                              stops: [0.4, 1.0],
                            ),
                          ),
                        ),
                        if (badge != null && badge!.isNotEmpty)
                          Positioned(
                            left: 12,
                            top: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.56),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.16),
                                ),
                              ),
                              child: Text(
                                badge!,
                                style: DesktopType.nano(DesktopPalette.onStage),
                              ),
                            ),
                          ),
                        Positioned(
                          left: 16,
                          right: 70,
                          bottom: 16,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: DesktopType.displaySm(
                                  DesktopPalette.onStage,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                caption,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: DesktopType.caption(
                                  DesktopPalette.onStage.withValues(
                                    alpha: 0.75,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          right: 14,
                          bottom: 14,
                          child: AnimatedOpacity(
                            duration: MotionToken.reduced(
                              context,
                              MotionToken.fast,
                            ),
                            curve: MotionToken.curve,
                            opacity: hovered ? 1 : 0,
                            alwaysIncludeSemantics: true,
                            child: DesktopHover(
                              builder:
                                  (context, playHovered) => GestureDetector(
                                    onTap: onPlay,
                                    behavior: HitTestBehavior.opaque,
                                    child: Tooltip(
                                      message: playLabel,
                                      child: Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: surface.accent,
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: 0.5,
                                              ),
                                              blurRadius: 24,
                                              offset: const Offset(0, 10),
                                              spreadRadius: -6,
                                            ),
                                          ],
                                        ),
                                        child: Icon(
                                          DesktopIcons.play,
                                          size: playHovered ? 22 : 20,
                                          color: surface.accentInk,
                                        ),
                                      ),
                                    ),
                                  ),
                            ),
                          ),
                        ),
                        if (progress != null)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: DesktopProgress(
                              fraction: progress!,
                              color: surface.accent,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
        ),
      ),
    );
  }
}

/// 音乐专辑格（样例 `.album-row` + `.album`）。
class DesktopListeningRow extends ConsumerWidget {
  const DesktopListeningRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final snapshotAsync = ref.watch(musicPortalSnapshotProvider);
    final snapshot = snapshotAsync.asData?.value;
    final tracks = snapshot?.recentTracks ?? const <MusicPortalTrack>[];
    if (snapshot == null && snapshotAsync.hasError) {
      return DesktopErrorView(
        message: errorReason(snapshotAsync.error!, l10n),
        onRetry: () => ref.invalidate(musicPortalSnapshotProvider),
        minHeightFactor: 0.22,
      );
    }
    final skeleton = LayoutBuilder(
      builder: (context, constraints) {
        const gap = 16.0;
        final count = constraints.maxWidth < 420 ? 3 : 4;
        final side = (constraints.maxWidth - gap * (count - 1)) / count;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var index = 0; index < count; index++)
              SizedBox(
                width: side,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AspectRatio(
                      aspectRatio: 1,
                      child: DesktopSkeletonBox(radius: 14, index: index * 3),
                    ),
                    const SizedBox(height: 10),
                    FractionallySizedBox(
                      widthFactor: 0.72,
                      alignment: Alignment.centerLeft,
                      child: DesktopSkeletonBox(
                        height: 12,
                        index: index * 3 + 1,
                      ),
                    ),
                    const SizedBox(height: 5),
                    FractionallySizedBox(
                      widthFactor: 0.48,
                      alignment: Alignment.centerLeft,
                      child: DesktopSkeletonBox(
                        height: 10,
                        index: index * 3 + 2,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
    final content =
        tracks.isEmpty
            ? DesktopEmpty(
              message: l10n.desktopHomeEmptyMusic,
              icon: DesktopIcons.music,
              actionLabel: l10n.desktopOpenMusic,
              onAction: () => context.go(DesktopRoutes.music),
            )
            : LayoutBuilder(
              builder: (context, constraints) {
                const gap = 16.0;
                final count = constraints.maxWidth < 420 ? 3 : 4;
                final side = (constraints.maxWidth - gap * (count - 1)) / count;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final track in tracks.take(count))
                      SizedBox(
                        width: side,
                        child: DesktopHoverLift(
                          onTap:
                              () => ref
                                  .read(musicPortalActionsProvider)
                                  .playTrackById(track.id),
                          onSecondaryTap:
                              () => ref
                                  .read(desktopShellProvider.notifier)
                                  .showDetail(
                                    DesktopDetailData(
                                      id: 'track:${track.id}',
                                      kind: 'track',
                                      title: track.title,
                                      subtitle:
                                          '${track.artistName} · ${track.albumTitle}',
                                      imageUrl: track.coverUrl,
                                      squareArt: true,
                                      factsLabel: l10n.desktopNavMusic,
                                      primary: DesktopDetailAction(
                                        label: l10n.desktopPlay,
                                        icon: DesktopIcons.play,
                                        onPressed:
                                            (ctx, r) => r
                                                .read(
                                                  musicPortalActionsProvider,
                                                )
                                                .playTrackById(track.id),
                                      ),
                                    ),
                                  ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AspectRatio(
                                aspectRatio: 1,
                                child: Container(
                                  clipBehavior: Clip.antiAlias,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(14),
                                    boxShadow: [
                                      BoxShadow(
                                        color: skin.shadow.first.color,
                                        blurRadius: 30,
                                        offset: const Offset(0, 14),
                                        spreadRadius: -12,
                                      ),
                                    ],
                                  ),
                                  child: DesktopCover(
                                    url: track.listCoverUrl ?? track.coverUrl,
                                    kind: DesktopCoverKind.music,
                                    fallbackIcon: DesktopIcons.music,
                                    cacheKey: 'desktop-home-${track.id}',
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: DesktopType.denseStrong(skin.text),
                              ),
                              Text(
                                track.artistName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: DesktopType.caption(skin.text3),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            );
    return DesktopSkeletonSwitcher(
      regionId: 'home-listening-row',
      hasData: snapshot != null,
      loading: snapshot == null && snapshotAsync.isLoading,
      skeleton: skeleton,
      child: content,
    );
  }
}
