import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/control_tokens.dart';
import 'package:omninest/app/theme/feature/music_colors.dart';
import 'package:omninest/core/auth/user_capabilities.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/core/widgets/mobile_sheet_semantics.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/core/widgets/mobile_sample_kit.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:omninest/core/widgets/workstation_dialog.dart';
import 'package:omninest/core/widgets/file_purge_confirmation.dart';
import 'package:omninest/features/files/presentation/widgets/media_import_button.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/application/music_daily_recommendation_controller.dart';
import 'package:omninest/features/music/application/music_scan_job_controller.dart';
import 'package:omninest/features/music/application/music_artist_albums_controller.dart';
import 'package:omninest/features/music/application/music_selection_controller.dart';
import 'package:omninest/features/music/application/music_playback_session.dart';
import 'package:omninest/features/music/application/music_platform_library_controller.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_add_to_playlist_sheet.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_cover_grid.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_create_playlist_dialog.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_models.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_primitives.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_track_list.dart';
import 'package:omninest/features/music/presentation/widgets/music_metadata_edit_dialog.dart';
import 'package:omninest/features/music/presentation/widgets/music_playback_controls.dart';
import 'package:omninest/app/theme/feature/music_chrome_colors.dart';
import 'package:omninest/core/feedback/omni_feedback.dart';

part 'music_deck_content_actions.dart';

part 'music_deck_content_support.dart';

part 'music_deck_local_management.dart';
part 'music_deck_content_sections.dart';

const int _homeContinueListeningLimit = 5;

/// Music Deck 主内容区。
class MusicDeckContent extends ConsumerWidget {
  const MusicDeckContent({
    required this.section,
    required this.libraryView,
    required this.sources,
    required this.collection,
    required this.onSectionChanged,
    required this.onLibraryViewChanged,
    required this.onOpenCollection,
    required this.onCloseCollection,
    super.key,
  });

  final MusicDeckSection section;
  final MusicDeckLibraryView libraryView;
  final Set<MusicPlatform> sources;
  final MusicDeckCollectionSelection? collection;
  final ValueChanged<MusicDeckSection> onSectionChanged;
  final ValueChanged<MusicDeckLibraryView> onLibraryViewChanged;
  final ValueChanged<MusicDeckCollectionSelection> onOpenCollection;
  final VoidCallback onCloseCollection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 仅订阅本分区会用到的中心状态切片，降低播放/收藏等无关变更的重建面。
    final center = ref.watch(
      musicCenterControllerProvider.select((async) => async.asData?.value),
    );
    final platform =
        ref.watch(musicPlatformLibraryProvider).asData?.value ??
        const MusicPlatformLibraryState();
    if (center == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final selectedCollection = collection;
    if (selectedCollection != null) {
      return _CollectionDetail(
        selection: selectedCollection,
        center: center,
        platform: platform,
        onBack: onCloseCollection,
        onOpenCollection: onOpenCollection,
      );
    }
    return switch (section) {
      MusicDeckSection.home => _HomeContent(
        center: center,
        platform: platform,
        sources: sources,
        onSectionChanged: onSectionChanged,
        onOpenCollection: onOpenCollection,
      ),
      MusicDeckSection.library => _LibraryContent(
        center: center,
        platform: platform,
        sources: sources,
        view: libraryView,
        onViewChanged: onLibraryViewChanged,
        onOpenCollection: onOpenCollection,
      ),
      MusicDeckSection.playlists => _PlaylistsContent(
        center: center,
        platform: platform,
        sources: sources,
        onOpenCollection: onOpenCollection,
      ),
      MusicDeckSection.favorites => _TrackSection(
        title: AppLocalizations.of(context).musicDeckFavorites,
        subtitle: AppLocalizations.of(context).musicDeckFavoritesSubtitle,
        // 收藏取服务端完整列表；按分区订阅，其他分区不为它多打一次请求。
        items: _favoriteItems(
          platform,
          sources,
          ref.watch(musicFavoriteTracksProvider).asData?.value ??
              const <MusicTrack>[],
        ),
        center: center,
      ),
      MusicDeckSection.recent => _TrackSection(
        title: AppLocalizations.of(context).musicDeckRecent,
        subtitle: AppLocalizations.of(context).musicDeckRecentSubtitle,
        items: _recentItems(center, sources),
        center: center,
        isRecentSection: true,
      ),
      MusicDeckSection.localManagement => _LocalManagementContent(
        center: center,
      ),
    };
  }
}

class _HomeContent extends ConsumerWidget {
  const _HomeContent({
    required this.center,
    required this.platform,
    required this.sources,
    required this.onSectionChanged,
    required this.onOpenCollection,
  });

  final MusicCenterState center;
  final MusicPlatformLibraryState platform;
  final Set<MusicPlatform> sources;
  final ValueChanged<MusicDeckSection> onSectionChanged;
  final ValueChanged<MusicDeckCollectionSelection> onOpenCollection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final dailyRecommendation = ref.watch(musicDailyRecommendationProvider);
    final dailySectionVisible =
        dailyRecommendation.isLoading ||
        dailyRecommendation.hasError ||
        dailyRecommendation.asData?.value != null;
    final recent = _recentItems(
      center,
      sources,
    ).take(_homeContinueListeningLimit).toList(growable: false);
    final covers = _playlistCoverItems(
      context,
      center,
      platform,
      sources,
      onOpenCollection,
    ).take(8).toList(growable: false);
    final hosted = MobileShellScope.isHosted(context);
    if (hosted) {
      return _hostedHomeBody(
        context,
        ref,
        l10n: l10n,
        center: center,
        covers: covers,
        recent: recent,
        sources: sources,
        dailyVisible: dailySectionVisible,
        onSectionChanged: onSectionChanged,
        onOpenCollection: onOpenCollection,
      );
    }
    // 桌面态卡片已带播放条避让，仅留小余量；紧凑态播放条在布局流内，保留完整避让。
    final compact = hosted || MediaQuery.sizeOf(context).width < 760;
    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: compact ? 112 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _NowPlayingFocusStrip(center: center),
          const SizedBox(height: 28),
          _SectionTitle(
            title: l10n.musicDeckContinueListening,
            actionLabel: l10n.musicViewAllSimple,
            onAction: () => onSectionChanged(MusicDeckSection.recent),
          ),
          const SizedBox(height: 10),
          if (recent.isEmpty)
            _InlineEmpty(message: l10n.musicDeckRecentEmpty)
          else
            SizedBox(
              // 条带不做无限滚动（滚动劫持）：截断 20 条，完整列表走历史页。
              height: (recent.length > 20 ? 20 : recent.length) * 66,
              child: MusicDeckTrackList(
                items: recent,
                scrollable: false,
                currentPlayableKey: center.currentItem?.playableKey,
                onPlay:
                    (index) => ref
                        .read(musicCenterControllerProvider.notifier)
                        .playItems(recent, startIndex: index),
                onToggleFavorite: _favoriteHandler(context, ref),
                onDelete: _deleteTrackHandler(context, ref),
                onEnqueue: _enqueueTrackHandler(context, ref),
                onAddToPlaylist: _addToPlaylistHandler(context, ref),
              ),
            ),
          const SizedBox(height: 28),
          if (dailySectionVisible) ...[
            _DailyRecommendationSection(
              recommendation: dailyRecommendation,
              onOpenCollection: onOpenCollection,
            ),
            const SizedBox(height: 28),
          ],
          _SectionTitle(
            title: l10n.musicDeckYourCollections,
            actionLabel: l10n.musicViewAllSimple,
            onAction: () => onSectionChanged(MusicDeckSection.playlists),
          ),
          const SizedBox(height: 12),
          if (covers.isEmpty)
            _InlineEmpty(message: l10n.musicPlaylistsEmptyHint)
          else
            MusicDeckCoverShelf(items: covers),
          if (platform.failures.isNotEmpty) ...[
            const SizedBox(height: 24),
            _PartialFailureBanner(
              message: l10n.musicDeckPartialSourceFailure,
              onRetry:
                  () =>
                      ref.read(musicPlatformLibraryProvider.notifier).refresh(),
            ),
          ],
        ],
      ),
    );
  }
}

class _DailyRecommendationSection extends ConsumerWidget {
  const _DailyRecommendationSection({
    required this.recommendation,
    required this.onOpenCollection,
  });

  final AsyncValue<DailyRecommendedTracks?> recommendation;
  final ValueChanged<MusicDeckCollectionSelection> onOpenCollection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final value = recommendation.asData?.value;
    final onOpenAll =
        value == null || value.tracks.isEmpty
            ? null
            : () =>
                onOpenCollection(DailyRecommendationMusicDeckCollection(value));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          title: l10n.musicDailyRecommendationSection,
          actionLabel: onOpenAll == null ? null : l10n.musicViewAllSimple,
          onAction: onOpenAll,
        ),
        const SizedBox(height: 12),
        recommendation.when(
          data: (value) {
            if (value == null) {
              return const SizedBox.shrink();
            }
            if (value.tracks.isEmpty) {
              return _InlineEmpty(message: l10n.musicDailyRecommendationEmpty);
            }
            if (value.tracks.length < 2) {
              final item = MusicDeckCoverItem(
                id:
                    '${value.platform}:daily:${value.recommendationDate.toIso8601String()}',
                title: l10n.musicDailyRecommendationTitle,
                subtitle: l10n.musicDailyRecommendationTrackCount(
                  value.tracks.length,
                ),
                imageUrl: value.listCoverUrl,
                platform: MusicPlatform.netease,
                overlayPlatformBadge: true,
                icon: Icons.today_rounded,
                onTap:
                    () => onOpenCollection(
                      DailyRecommendationMusicDeckCollection(value),
                    ),
              );
              return MusicDeckCoverShelf(items: [item]);
            }
            final platform = MusicPlatform.fromApiValue(value.platform);
            // 队列载入全量推荐曲目（替换旧队列），卡片仅展示前 10 张。
            final playableItems = value.tracks
                .map(MusicPlayableItem.online)
                .toList(growable: false);
            final items = <MusicDeckCoverItem>[
              for (
                var index = 0;
                index < playableItems.length && index < 10;
                index++
              )
                MusicDeckCoverItem(
                  id:
                      '${value.platform}:daily:${value.recommendationDate.toIso8601String()}:${playableItems[index].playableKey}',
                  title: playableItems[index].track.title,
                  subtitle: playableItems[index].track.artistName,
                  imageUrl: playableItems[index].track.listCoverUrl,
                  platform: platform,
                  overlayPlatformBadge: true,
                  onTap:
                      () => ref
                          .read(musicCenterControllerProvider.notifier)
                          .playItems(playableItems, startIndex: index),
                ),
            ];
            return MusicDeckCoverShelf(items: items);
          },
          error:
              (error, stackTrace) => _PartialFailureBanner(
                message: l10n.musicDailyRecommendationLoadFailed,
                onRetry:
                    () =>
                        ref
                            .read(musicDailyRecommendationProvider.notifier)
                            .retry(),
              ),
          loading: () => const _DailyRecommendationSkeleton(),
          // 不开启「reload 期间保留旧值」：isReloading 的唯一来源是会话世代
          // 变化（换号），此时必须显示骨架而非上一账号数据；同账号刷新
          // 走 invalidate（isRefreshing），默认 skipLoadingOnRefresh 已
          // 保证不闪骨架。
        ),
      ],
    );
  }
}

class _DailyRecommendationSkeleton extends StatelessWidget {
  const _DailyRecommendationSkeleton();

  @override
  Widget build(BuildContext context) {
    // 卡式槽位等数时保持版面即可：岛内已有内容与底部进度各自有动画，
    // 这里再画一个转圈就是同屏多份加载动画。
    return const SizedBox(
      width: 142,
      height: 196,
      child: MobileSkeletonBlock(height: 196, width: 142),
    );
  }
}

class _NowPlayingFocusStrip extends ConsumerWidget {
  const _NowPlayingFocusStrip({required this.center});

  final MusicCenterState center;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final track = center.activeTrack;
    return MusicDeckGlass(
      opacity: 0.16,
      blur: 10,
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 520;
          final coverSize = compact ? 82.0 : 116.0;
          return ConstrainedBox(
            constraints: BoxConstraints(minHeight: compact ? 96 : 142),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: coverSize,
                  child: MusicDeckArtwork(
                    title: track?.title ?? '',
                    imageUrl: track?.listCoverUrl,
                  ),
                ),
                SizedBox(width: compact ? 13 : 20),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        center.currentItem == null
                            ? l10n.musicDeckLibraryReady
                            : l10n.musicDeckNowPlaying,
                        // 眉标用中性次级色；品牌青绿仅保留给交互与激活态，
                        // 避免大面积绿色文字主导页面。
                        style: TextStyle(
                          color: context.musicColors.onSurfaceVariant,
                          fontSize: AppTypography.labelSmall,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                      ),
                      SizedBox(height: compact ? 4 : 7),
                      Text(
                        track?.title ?? l10n.musicDeckSelectTrack,
                        maxLines: compact ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.musicColors.onSurface,
                          fontSize: compact ? 17 : 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        track == null
                            ? l10n.musicDeckLibrarySummary(
                              center.tracks.length,
                              center.albums.length,
                            )
                            : '${track.artistName} · ${track.albumTitle}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.musicColors.onSurfaceVariant,
                          fontSize: compact ? 11 : 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                MusicPlaybackButton(
                  buttonSize:
                      compact
                          ? MusicPlaybackButtonSize.compact
                          : MusicPlaybackButtonSize.regular,
                  isPlaying: center.isPlaying,
                  tooltip: center.isPlaying ? l10n.musicPause : l10n.musicPlay,
                  onPressed:
                      track == null
                          ? null
                          : () =>
                              ref
                                  .read(musicCenterControllerProvider.notifier)
                                  .togglePlayback(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _LibraryContent extends ConsumerWidget {
  const _LibraryContent({
    required this.center,
    required this.platform,
    required this.sources,
    required this.view,
    required this.onViewChanged,
    required this.onOpenCollection,
  });

  final MusicCenterState center;
  final MusicPlatformLibraryState platform;
  final Set<MusicPlatform> sources;
  final MusicDeckLibraryView view;
  final ValueChanged<MusicDeckLibraryView> onViewChanged;
  final ValueChanged<MusicDeckCollectionSelection> onOpenCollection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final selection = ref.watch(musicSelectionControllerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selection.selectionMode)
          _MusicBatchActionBar(center: center, selection: selection)
        else
          _LibraryHeader(view: view, onViewChanged: onViewChanged),
        const SizedBox(height: 14),
        Expanded(
          child: switch (view) {
            MusicDeckLibraryView.tracks => MusicDeckTrackList(
              items: _libraryItems(center, platform, sources),
              currentPlayableKey: center.currentItem?.playableKey,
              selectedIds:
                  selection.selectionMode ? selection.selectedIds : null,
              onLongPress:
                  selection.selectionMode
                      ? null
                      : (item) => ref
                          .read(musicSelectionControllerProvider.notifier)
                          .enterSelectionMode(item.track.id),
              onPlay: (index) {
                if (selection.selectionMode) {
                  final item = _libraryItems(center, platform, sources)[index];
                  ref
                      .read(musicSelectionControllerProvider.notifier)
                      .toggle(item.track.id);
                  return;
                }
                final items = _libraryItems(center, platform, sources);
                ref
                    .read(musicCenterControllerProvider.notifier)
                    .playItems(
                      items,
                      startIndex: index,
                      source: MusicQueueSource(
                        kind: MusicQueueSourceKind.library,
                        platforms:
                            sources.map((item) => item.apiValue).toList(),
                      ),
                    );
              },
              onToggleFavorite: _favoriteHandler(context, ref),
              onDelete: _deleteTrackHandler(context, ref),
              onEnqueue: _enqueueTrackHandler(context, ref),
              onAddToPlaylist: _addToPlaylistHandler(context, ref),
              onReachEnd:
                  (center.hasMoreTracks ||
                          platform.hasMoreLikedTracks(
                            sources
                                .where((item) => item != MusicPlatform.local)
                                .map((item) => item.apiValue),
                          ))
                      ? () {
                        // 曲库列表混排本地曲目与在线喜欢列表：两端各自续载。
                        if (center.hasMoreTracks) {
                          ref
                              .read(musicCenterControllerProvider.notifier)
                              .loadMoreTracks();
                        }
                        ref
                            .read(musicPlatformLibraryProvider.notifier)
                            .loadMoreLikedTracks(
                              sources
                                  .where((item) => item != MusicPlatform.local)
                                  .map((item) => item.apiValue),
                            );
                      }
                      : null,
              footer:
                  (center.tracksLoadingMore || platform.loadingMoreLiked)
                      ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : null,
            ),
            MusicDeckLibraryView.albums => MusicDeckCoverGrid(
              items: _albumCoverItems(
                center,
                platform,
                sources,
                onOpenCollection,
              ),
              emptyTitle: l10n.musicLibraryAlbumsEmptyTitle,
              emptyMessage: l10n.musicLibraryAlbumsEmptyMessage,
            ),
            MusicDeckLibraryView.genres => _GenresContent(
              center: center,
              platform: platform,
              sources: sources,
            ),
            MusicDeckLibraryView.artists => MusicDeckCoverGrid(
              items: _artistCoverItems(
                l10n,
                center,
                platform,
                sources,
                onOpenCollection,
              ),
              emptyTitle: l10n.musicLibraryArtistsEmptyTitle,
              emptyMessage: l10n.musicLibraryArtistsEmptyMessage,
            ),
          },
        ),
      ],
    );
  }
}

class _PlaylistsContent extends ConsumerWidget {
  const _PlaylistsContent({
    required this.center,
    required this.platform,
    required this.sources,
    required this.onOpenCollection,
  });

  final MusicCenterState center;
  final MusicPlatformLibraryState platform;
  final Set<MusicPlatform> sources;
  final ValueChanged<MusicDeckCollectionSelection> onOpenCollection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final items = _playlistCoverItems(
      context,
      center,
      platform,
      sources,
      onOpenCollection,
      onEdit: (playlist) => _showEditPlaylistDialog(context, ref, playlist),
      onDelete: (playlist) => _confirmDeletePlaylist(context, ref, playlist),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ContentHeader(
          title: l10n.musicDeckPlaylists,
          subtitle: l10n.musicDeckPlaylistsSubtitle,
          trailing:
              sources.contains(MusicPlatform.local)
                  ? OutlinedButton.icon(
                    onPressed: () => _showCreatePlaylistDialog(context, ref),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.musicColors.onSurface,
                    ),
                    icon: const Icon(
                      Icons.add_rounded,
                      size: AppControlTokens.buttonIconSize,
                    ),
                    label: Text(l10n.musicCreatePlaylist),
                  )
                  : null,
        ),
        const SizedBox(height: 16),
        Expanded(
          child:
              items.isEmpty
                  ? _InlineEmpty(message: l10n.musicPlaylistsEmptyHint)
                  : MusicDeckCoverGrid(items: items),
        ),
      ],
    );
  }
}
