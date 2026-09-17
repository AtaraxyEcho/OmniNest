import 'package:flutter/material.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/music_colors.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/core/widgets/file_purge_confirmation.dart';
import 'package:omninest/features/files/presentation/widgets/media_import_button.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/application/music_daily_recommendation_controller.dart';
import 'package:omninest/features/music/application/music_scan_job_controller.dart';
import 'package:omninest/features/music/application/music_artist_albums_controller.dart';
import 'package:omninest/features/music/application/music_selection_controller.dart';
import 'package:omninest/features/music/application/music_platform_library_controller.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_add_to_playlist_sheet.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_cover_grid.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_create_playlist_dialog.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_models.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_primitives.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_track_list.dart';
import 'package:omninest/features/music/presentation/widgets/music_playback_controls.dart';

part 'music_deck_content_support.dart';

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
    final center = ref.watch(musicCenterControllerProvider).asData?.value;
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
        items: _favoriteItems(center, platform, sources),
        center: center,
      ),
      MusicDeckSection.recent => _TrackSection(
        title: AppLocalizations.of(context).musicDeckRecent,
        subtitle: AppLocalizations.of(context).musicDeckRecentSubtitle,
        items: _recentItems(center, sources),
        center: center,
        isRecentSection: true,
      ),
      MusicDeckSection.offline => const _OfflineContent(),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 112),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!hosted) ...[
            _NowPlayingFocusStrip(center: center),
            const SizedBox(height: 28),
          ],
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
              height: recent.length * 66,
              child: MusicDeckTrackList(
                items: recent,
                scrollable: false,
                currentPlayableKey: center.currentItem?.playableKey,
                onPlay:
                    (index) => ref
                        .read(musicCenterControllerProvider.notifier)
                        .playItems(recent, startIndex: index),
                onToggleFavorite: _favoriteHandler(ref),
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
                imageUrl: value.coverUrl,
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
                  imageUrl: playableItems[index].track.coverUrl,
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
          // provider 因依赖状态重建时保留旧数据，避免封面卡闪烁加载。
          skipLoadingOnReload: true,
        ),
      ],
    );
  }
}

class _DailyRecommendationSkeleton extends StatelessWidget {
  const _DailyRecommendationSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 142,
      height: 196,
      child: Center(
        child: SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
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
                    imageUrl: track?.coverUrl,
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
                        style: TextStyle(
                          color: context.musicColors.primary,
                          fontSize: AppTypography.labelSmall,
                          fontWeight: FontWeight.w800,
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
                      : () => ref
                          .read(musicSelectionControllerProvider.notifier)
                          .enterSelectionMode(center.tracks.first.id),
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
                    .playItems(items, startIndex: index);
              },
              onToggleFavorite: _favoriteHandler(ref),
              onDelete: _deleteTrackHandler(context, ref),
              onEnqueue: _enqueueTrackHandler(context, ref),
              onAddToPlaylist: _addToPlaylistHandler(context, ref),
              onReachEnd:
                  center.hasMoreTracks
                      ? () =>
                          ref
                              .read(musicCenterControllerProvider.notifier)
                              .loadMoreTracks()
                      : null,
              footer:
                  center.tracksLoadingMore
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
                  ? FilledButton.icon(
                    onPressed: () => _showCreatePlaylistDialog(context, ref),
                    icon: const Icon(Icons.add_rounded, size: 18),
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

class _TrackSection extends ConsumerWidget {
  const _TrackSection({
    required this.title,
    required this.subtitle,
    required this.items,
    required this.center,
    this.isRecentSection = false,
  });

  final String title;
  final String subtitle;
  final List<MusicPlayableItem> items;
  final MusicCenterState center;
  final bool isRecentSection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ContentHeader(
          title: title,
          subtitle: subtitle,
          trailing:
              isRecentSection
                  ? TextButton(
                    onPressed: () => context.push('/music/history'),
                    child: Text(l10n.musicHistoryViewAll),
                  )
                  : null,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: MusicDeckTrackList(
            items: items,
            currentPlayableKey: center.currentItem?.playableKey,
            onPlay:
                (index) => ref
                    .read(musicCenterControllerProvider.notifier)
                    .playItems(items, startIndex: index),
            onToggleFavorite: _favoriteHandler(ref),
            onDelete: _deleteTrackHandler(context, ref),
            onEnqueue: _enqueueTrackHandler(context, ref),
            onAddToPlaylist: _addToPlaylistHandler(context, ref),
          ),
        ),
      ],
    );
  }
}

class _CollectionDetail extends ConsumerWidget {
  const _CollectionDetail({
    required this.selection,
    required this.center,
    required this.platform,
    required this.onBack,
  });

  final MusicDeckCollectionSelection selection;
  final MusicCenterState center;
  final MusicPlatformLibraryState platform;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (
      title,
      subtitle,
      imageUrl,
      source,
      items,
      loading,
    ) = switch (selection) {
      LocalMusicDeckCollection(:final playlist) => (
        playlist.name,
        playlist.description ??
            AppLocalizations.of(context).musicDeckLocalPlaylist,
        playlist.coverUrl,
        MusicPlatform.local,
        center.selectedPlaylist?.id == playlist.id
            ? center.selectedPlaylistTracks
                .map(MusicPlayableItem.local)
                .toList(growable: false)
            : const <MusicPlayableItem>[],
        false,
      ),
      OnlineMusicDeckCollection(:final playlist) => (
        playlist.name,
        playlist.ownerName,
        platform.coverUrlForPlaylist(playlist),
        MusicPlatform.fromApiValue(playlist.platform),
        (platform.playlistTracks['${playlist.platform}:${playlist.playlistId}'] ??
                const <OnlineTrack>[])
            .map(MusicPlayableItem.online)
            .toList(growable: false),
        platform.loadingPlaylistKeys.contains(
          '${playlist.platform}:${playlist.playlistId}',
        ),
      ),
      DailyRecommendationMusicDeckCollection(:final recommendation) => (
        AppLocalizations.of(context).musicDailyRecommendationTitle,
        AppLocalizations.of(
          context,
        ).musicDailyRecommendationTrackCount(recommendation.tracks.length),
        recommendation.coverUrl,
        MusicPlatform.fromApiValue(recommendation.platform),
        recommendation.tracks
            .map(MusicPlayableItem.online)
            .toList(growable: false),
        false,
      ),
      AlbumMusicDeckCollection(:final album) => (
        album.title,
        album.artistName,
        album.coverUrl,
        MusicPlatform.local,
        center.selectedAlbum?.id == album.id
            ? center.selectedAlbumTracks
                .map(MusicPlayableItem.local)
                .toList(growable: false)
            : const <MusicPlayableItem>[],
        false,
      ),
      ArtistMusicDeckCollection(:final artist) => (
        artist.name,
        AppLocalizations.of(context).musicDeckTrackCount(artist.trackCount),
        artist.avatarUrl,
        MusicPlatform.local,
        center.selectedArtist?.id == artist.id
            ? center.selectedArtistTracks
                .map(MusicPlayableItem.local)
                .toList(growable: false)
            : const <MusicPlayableItem>[],
        false,
      ),
      OnlineAlbumMusicDeckCollection(
        :final platform,
        :final title,
        :final artistName,
        :final coverUrl,
        :final tracks,
      ) =>
        (
          title,
          artistName,
          coverUrl,
          platform,
          tracks.map(MusicPlayableItem.online).toList(growable: false),
          false,
        ),
      OnlineArtistMusicDeckCollection(
        :final platform,
        :final name,
        :final coverUrl,
        :final tracks,
      ) =>
        (
          name,
          AppLocalizations.of(context).musicDeckTrackCount(tracks.length),
          coverUrl,
          platform,
          tracks.map(MusicPlayableItem.online).toList(growable: false),
          false,
        ),
    };
    return Column(
      children: [
        _CollectionDetailHeader(
          title: title,
          subtitle: subtitle,
          imageUrl: imageUrl,
          source: source,
          onBack: onBack,
          onPlay:
              items.isEmpty
                  ? null
                  : () => ref
                      .read(musicCenterControllerProvider.notifier)
                      .playItems(items, startIndex: 0),
        ),
        const SizedBox(height: 18),
        if (selection case ArtistMusicDeckCollection(:final artist))
          _ArtistAlbumsShelf(artistId: artist.id),
        Expanded(
          child:
              loading
                  ? const Center(child: CircularProgressIndicator())
                  : MusicDeckTrackList(
                    items: items,
                    currentPlayableKey: center.currentItem?.playableKey,
                    onPlay:
                        (index) => ref
                            .read(musicCenterControllerProvider.notifier)
                            .playItems(items, startIndex: index),
                    onToggleFavorite: _favoriteHandler(ref),
                    onDelete: _deleteTrackHandler(context, ref),
                    onEnqueue: _enqueueTrackHandler(context, ref),
                    onAddToPlaylist: _addToPlaylistHandler(context, ref),
                  ),
        ),
      ],
    );
  }
}

class _OfflineContent extends StatelessWidget {
  const _OfflineContent();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ContentHeader(
          title: l10n.musicDeckOffline,
          subtitle: l10n.musicDeckOfflineSubtitle,
        ),
        const SizedBox(height: 18),
        Expanded(child: _InlineEmpty(message: l10n.musicDeckOfflineEmpty)),
      ],
    );
  }
}

class _LocalManagementContent extends ConsumerWidget {
  const _LocalManagementContent({required this.center});

  final MusicCenterState center;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scanJob = ref.watch(musicScanJobControllerProvider);
    final activeScan = scanJob.job ?? center.lastScanJob;
    final scanRunning = scanJob.polling;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ContentHeader(
          title: l10n.musicDeckLocalManagement,
          subtitle: l10n.musicLocalManagementSubtitle,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              MediaImportButton(
                subsystemDirectory: 'Music',
                acceptedExtensions: const [
                  'mp3',
                  'flac',
                  'aac',
                  'm4a',
                  'ogg',
                  'opus',
                  'wav',
                  'wma',
                ],
                onImportComplete: () async {
                  // 上传完成后立即扫描，把新文件导入曲库并刷新列表。
                  await ref
                      .read(musicScanJobControllerProvider.notifier)
                      .startScan();
                  await ref
                      .read(musicCenterControllerProvider.notifier)
                      .refresh();
                },
                style: ImportButtonStyle.textButton,
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () => _confirmScrapeLibrary(context, ref),
                icon: const Icon(Icons.travel_explore_rounded, size: 18),
                label: Text(l10n.musicScrapeLibrary),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed:
                    scanRunning ? null : () => _confirmStartScan(context, ref),
                icon: const Icon(Icons.radar_rounded, size: 18),
                label: Text(l10n.musicStartScan),
              ),
            ],
          ),
        ),
        if (activeScan != null) ...[
          const SizedBox(height: 12),
          Text(
            l10n.musicScanStatus(
              activeScan.id,
              activeScan.status,
              activeScan.progress,
              activeScan.scannedFiles,
            ),
            style: TextStyle(
              color: context.musicColors.onSurfaceVariant,
              fontSize: AppTypography.bodySmall,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: activeScan.progress > 0 ? activeScan.progress / 100 : null,
              minHeight: 4,
            ),
          ),
          if (activeScan.message != null && activeScan.message!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              activeScan.message!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.musicColors.onSurfaceVariant,
                fontSize: AppTypography.bodySmall,
              ),
            ),
          ],
          if (scanJob.timedOut)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l10n.musicScanPollTimeout,
                style: TextStyle(
                  color: context.musicColors.onSurfaceVariant,
                  fontSize: AppTypography.bodySmall,
                ),
              ),
            ),
        ],
        const SizedBox(height: 16),
        Expanded(
          child:
              center.tracks.isEmpty
                  ? _InlineEmpty(message: l10n.musicNoMetadataHint)
                  : ListView.separated(
                    itemCount: center.tracks.length,
                    separatorBuilder:
                        (context, index) => Divider(
                          color: context.musicColors.outline,
                          height: 1,
                        ),
                    itemBuilder: (context, index) {
                      final track = center.tracks[index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        leading: SizedBox.square(
                          dimension: 44,
                          child: MusicDeckArtwork(
                            title: track.title,
                            imageUrl: track.coverUrl,
                          ),
                        ),
                        title: Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.musicColors.onSurface,
                          ),
                        ),
                        subtitle: Text(
                          '${track.artistName} · ${track.albumTitle}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.musicColors.onSurfaceVariant,
                          ),
                        ),
                        trailing: IconButton(
                          tooltip: l10n.musicEditMetadata,
                          onPressed:
                              () => context.push(
                                '/music/tracks/${track.id}/metadata',
                              ),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                      );
                    },
                  ),
        ),
      ],
    );
  }
}

Future<void> _confirmStartScan(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder:
        (dialogContext) => AlertDialog(
          title: Text(l10n.musicStartScan),
          content: Text(l10n.musicScanConfirmMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.musicCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.musicStartScan),
            ),
          ],
        ),
  );
  if (confirmed != true || !context.mounted) {
    return;
  }
  await ref.read(musicScanJobControllerProvider.notifier).startScan();
}

Future<void> _confirmScrapeLibrary(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder:
        (dialogContext) => AlertDialog(
          title: Text(l10n.musicScrapeLibraryConfirmTitle),
          content: Text(l10n.musicScrapeLibraryConfirmMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.musicCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.musicScrapeLibrary),
            ),
          ],
        ),
  );
  if (confirmed != true || !context.mounted) {
    return;
  }
  try {
    await ref
        .read(musicCenterControllerProvider.notifier)
        .scrapeLibrary(force: true);
  } on Exception {
    // 命令层已把失败写入中心状态 errorMessage，由页面统一展示。
  }
}

/// 曲库批量操作条：全选、加入歌单、下一首播放与退出多选。
class _MusicBatchActionBar extends ConsumerWidget {
  const _MusicBatchActionBar({required this.center, required this.selection});

  final MusicCenterState center;
  final MusicSelectionState selection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = context.musicColors;
    final notifier = ref.read(musicSelectionControllerProvider.notifier);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outline.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Text(
            l10n.musicSelectionCount(selection.selectedIds.length),
            style: TextStyle(
              color: colors.onSurface,
              fontSize: AppTypography.bodyMedium,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed:
                () =>
                    notifier.selectAll(center.tracks.map((track) => track.id)),
            child: Text(l10n.musicSelectionSelectAll),
          ),
          TextButton(
            onPressed:
                selection.hasSelection
                    ? () => _addToPlaylist(context, ref)
                    : null,
            child: Text(l10n.musicAddToPlaylist),
          ),
          TextButton(
            onPressed:
                selection.hasSelection ? () => _enqueue(context, ref) : null,
            child: Text(l10n.musicPlayNext),
          ),
          IconButton(
            tooltip: l10n.musicSelectionExit,
            onPressed: notifier.exitSelectionMode,
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ),
    );
  }

  Future<void> _addToPlaylist(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final playlist = await _showPlaylistPicker(context, ref);
    if (playlist == null || !context.mounted) {
      return;
    }
    final notifier = ref.read(musicSelectionControllerProvider.notifier);
    final results = await notifier.addSelectedToPlaylist(
      playlist,
      center.tracks,
    );
    if (!context.mounted) {
      return;
    }
    final success = results.where((item) => item.success).length;
    final failedTitles =
        results
            .where((item) => !item.success)
            .map((item) => item.title)
            .toList();
    final failed = failedTitles.length;
    final text =
        failed == 0
            ? l10n.musicBatchAddedToPlaylist(success, playlist.name)
            : '${l10n.musicBatchPartial(success, failed)}'
                ' · ${l10n.musicBatchFailedTitles(failedTitles.join(', '))}';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _enqueue(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(musicSelectionControllerProvider.notifier);
    final results = notifier.enqueueSelected(center.tracks);
    notifier.exitSelectionMode();
    if (!context.mounted) {
      return;
    }
    final success = results.where((item) => item.success).length;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.musicBatchEnqueued(success))));
  }

  Future<MusicPlaylist?> _showPlaylistPicker(
    BuildContext context,
    WidgetRef ref,
  ) async {
    MusicPlaylist? selected;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final playlists = center.playlists;
        return SafeArea(
          child: Material(
            color: Theme.of(sheetContext).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final playlist in playlists)
                  ListTile(
                    title: Text(playlist.name),
                    onTap: () {
                      selected = playlist;
                      Navigator.of(sheetContext).pop();
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
    return selected;
  }
}

/// 艺人详情页的专辑横向封面架，进入详情时按需加载。
class _ArtistAlbumsShelf extends ConsumerStatefulWidget {
  const _ArtistAlbumsShelf({required this.artistId});

  final String artistId;

  @override
  ConsumerState<_ArtistAlbumsShelf> createState() => _ArtistAlbumsShelfState();
}

class _ArtistAlbumsShelfState extends ConsumerState<_ArtistAlbumsShelf> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref
            .read(musicArtistAlbumsControllerProvider.notifier)
            .ensureLoaded(widget.artistId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(musicArtistAlbumsControllerProvider);
    final albums = state.albumsByArtist[widget.artistId];
    if (albums == null || albums.isEmpty) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final items = [
      for (final album in albums)
        MusicDeckCoverItem(
          id: album.id,
          title: album.title,
          subtitle: l10n.musicDeckTrackCount(album.trackCount),
          imageUrl: album.coverUrl,
          icon: Icons.album_rounded,
          onTap:
              () => ref
                  .read(musicCenterControllerProvider.notifier)
                  .openAlbum(album),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: MusicDeckCoverShelf(items: items),
    );
  }
}

/// 流派浏览：客户端聚合本地曲目 genre → 计数，点按流派过滤曲目。
class _GenresContent extends ConsumerStatefulWidget {
  const _GenresContent({
    required this.center,
    required this.platform,
    required this.sources,
  });

  final MusicCenterState center;
  final MusicPlatformLibraryState platform;
  final Set<MusicPlatform> sources;

  @override
  ConsumerState<_GenresContent> createState() => _GenresContentState();
}

class _GenresContentState extends ConsumerState<_GenresContent> {
  String? _selectedGenre;

  Map<String, List<MusicTrack>> _groupByGenre(List<MusicTrack> tracks) {
    final result = <String, List<MusicTrack>>{};
    for (final track in tracks) {
      final genre = track.genre?.trim();
      if (genre == null || genre.isEmpty) {
        continue;
      }
      result.putIfAbsent(genre, () => []).add(track);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final byGenre = _groupByGenre(widget.center.tracks);
    final genres = byGenre.keys.toList()..sort();
    if (genres.isEmpty) {
      return _InlineEmpty(message: l10n.musicGenresEmpty);
    }
    final selectedGenre =
        _selectedGenre != null && genres.contains(_selectedGenre)
            ? _selectedGenre!
            : null;
    final filteredTracks =
        selectedGenre == null ? <MusicTrack>[] : byGenre[selectedGenre]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              for (final genre in genres)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('$genre (${byGenre[genre]!.length})'),
                    selected: selectedGenre == genre,
                    onSelected: (selected) {
                      setState(() {
                        _selectedGenre = selected ? genre : null;
                      });
                    },
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child:
              selectedGenre == null
                  ? Center(
                    child: Text(
                      l10n.musicGenresPickHint,
                      style: TextStyle(
                        color: context.musicColors.onSurfaceVariant,
                      ),
                    ),
                  )
                  : MusicDeckTrackList(
                    items: filteredTracks
                        .map(MusicPlayableItem.local)
                        .toList(growable: false),
                    currentPlayableKey: widget.center.currentItem?.playableKey,
                    onPlay:
                        (index) => ref
                            .read(musicCenterControllerProvider.notifier)
                            .playItems(
                              filteredTracks
                                  .map(MusicPlayableItem.local)
                                  .toList(growable: false),
                              startIndex: index,
                            ),
                    onToggleFavorite: _favoriteHandler(ref),
                    onDelete: _deleteTrackHandler(context, ref),
                    onEnqueue: _enqueueTrackHandler(context, ref),
                    onAddToPlaylist: _addToPlaylistHandler(context, ref),
                  ),
        ),
      ],
    );
  }
}
