part of 'music_deck_content.dart';

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
            onToggleFavorite: _favoriteHandler(context, ref),
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
    required this.onOpenCollection,
  });

  final MusicDeckCollectionSelection selection;
  final MusicCenterState center;
  final MusicPlatformLibraryState platform;
  final VoidCallback onBack;

  /// 从歌手详情点专辑时要切换外层集合视图，光改中心状态界面仍停在原地。
  final ValueChanged<MusicDeckCollectionSelection> onOpenCollection;

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
        playlist.listCoverUrl,
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
        (platform
                    .playlistTracks['${playlist.platform}:${playlist.playlistId}']
                    ?.items ??
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
        recommendation.listCoverUrl,
        MusicPlatform.fromApiValue(recommendation.platform),
        recommendation.tracks
            .map(MusicPlayableItem.online)
            .toList(growable: false),
        false,
      ),
      AlbumMusicDeckCollection(:final album) => (
        album.title,
        album.artistName,
        album.listCoverUrl,
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
        artist.listCoverUrl,
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
    final queueSource = switch (selection) {
      LocalMusicDeckCollection(:final playlist) => MusicQueueSource(
        kind: MusicQueueSourceKind.playlist,
        id: playlist.id,
        title: playlist.name,
      ),
      AlbumMusicDeckCollection(:final album) => MusicQueueSource(
        kind: MusicQueueSourceKind.album,
        id: album.id,
        title: album.title,
      ),
      ArtistMusicDeckCollection(:final artist) => MusicQueueSource(
        kind: MusicQueueSourceKind.artist,
        id: artist.id,
        title: artist.name,
      ),
      _ => const MusicQueueSource(),
    };
    // 在线歌单只展示已加载页：入队前由播放命令补齐整表。
    final platformPlaylist = switch (selection) {
      OnlineMusicDeckCollection(:final playlist) => playlist,
      _ => null,
    };
    final playlistKey =
        platformPlaylist == null
            ? null
            : '${platformPlaylist.platform}:${platformPlaylist.playlistId}';
    final canLoadMorePlaylistTracks =
        playlistKey != null &&
        (platform.playlistTracks[playlistKey]?.hasMore ?? false);
    final playlistTracksLoadingMore =
        playlistKey != null &&
        platform.appendingPlaylistKeys.contains(playlistKey);
    void playAt(int index) {
      final centerNotifier = ref.read(musicCenterControllerProvider.notifier);
      if (platformPlaylist != null) {
        unawaited(
          centerNotifier.playPlatformPlaylist(
            platformPlaylist,
            startItem: items[index],
            source: queueSource,
          ),
        );
        return;
      }
      if (center.detailPaging.hasMore) {
        // 播放队列按来源全量重建：本地详情滚动窗口未满时先补齐全量再入队。
        unawaited(() async {
          final List<MusicTrack> complete = await switch (selection) {
            LocalMusicDeckCollection() =>
              centerNotifier.ensureCompletePlaylistTracks(),
            AlbumMusicDeckCollection() =>
              centerNotifier.ensureCompleteAlbumTracks(),
            ArtistMusicDeckCollection() =>
              centerNotifier.ensureCompleteArtistTracks(),
            _ => Future.value(const <MusicTrack>[]),
          };
          final target = items[index];
          final completeItems = complete
              .map<MusicPlayableItem>(MusicPlayableItem.local)
              .toList(growable: false);
          final startIndex = completeItems.indexWhere(
            (candidate) => candidate.playableKey == target.playableKey,
          );
          await centerNotifier.playItems(
            completeItems,
            startIndex: startIndex < 0 ? 0 : startIndex,
            source: queueSource,
          );
        }());
        return;
      }
      unawaited(
        centerNotifier.playItems(items, startIndex: index, source: queueSource),
      );
    }

    return Column(
      children: [
        _CollectionDetailHeader(
          title: title,
          subtitle: subtitle,
          imageUrl: imageUrl,
          source: source,
          onBack: onBack,
          onPlay: items.isEmpty ? null : () => playAt(0),
        ),
        const SizedBox(height: 18),
        if (selection case ArtistMusicDeckCollection(:final artist))
          _ArtistAlbumsShelf(
            artistId: artist.id,
            onOpenAlbum:
                (album) => onOpenCollection(AlbumMusicDeckCollection(album)),
          ),
        Expanded(
          child:
              loading && items.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : MusicDeckTrackList(
                    items: items,
                    currentPlayableKey: center.currentItem?.playableKey,
                    onPlay: playAt,
                    onReachEnd: () {
                      if (platformPlaylist != null) {
                        if (canLoadMorePlaylistTracks) {
                          unawaited(
                            ref
                                .read(musicPlatformLibraryProvider.notifier)
                                .loadMorePlaylistTracks(platformPlaylist),
                          );
                        }
                        return;
                      }
                      if (center.detailPaging.hasMore &&
                          !center.detailPaging.loadingMore) {
                        final notifier = ref.read(
                          musicCenterControllerProvider.notifier,
                        );
                        unawaited(switch (selection) {
                          LocalMusicDeckCollection() =>
                            notifier.loadMorePlaylistTracks(),
                          AlbumMusicDeckCollection() =>
                            notifier.loadMoreAlbumTracks(),
                          ArtistMusicDeckCollection() =>
                            notifier.loadMoreArtistTracks(),
                          _ => Future.value(),
                        });
                      }
                    },
                    footer:
                        playlistTracksLoadingMore
                            ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : null,
                    onToggleFavorite: _favoriteHandler(context, ref),
                    onDelete:
                        selection is LocalMusicDeckCollection
                            ? _removeFromPlaylistHandler(context, ref)
                            : _deleteTrackHandler(context, ref),
                    onEnqueue: _enqueueTrackHandler(context, ref),
                    onAddToPlaylist: _addToPlaylistHandler(context, ref),
                  ),
        ),
      ],
    );
  }
}

Future<void> _confirmStartScan(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showWorkstationDialog<bool>(
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
  final confirmed = await showWorkstationDialog<bool>(
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

/// 托管 Home（样例 MusicModule Home 段）：NOW PLAYING 卡 + 每日/收藏
/// 专辑轨 + 编号衬线续听行。
Widget _hostedHomeBody(
  BuildContext context,
  WidgetRef ref, {
  required AppLocalizations l10n,
  required MusicCenterState center,
  required List<MusicDeckCoverItem> covers,
  required List<MusicPlayableItem> recent,
  required Set<MusicPlatform> sources,
  required bool dailyVisible,
  required ValueChanged<MusicDeckSection> onSectionChanged,
}) {
  final track = center.activeTrack;
  // 播放会话在测试环境无服务器配置：NOW PLAYING 卡不读会话位置，
  // 进度文本用 0:00 / 总时长（样例即静态卡片）。
  const position = Duration.zero;
  final duration =
      track == null
          ? Duration.zero
          : Duration(seconds: track.durationSeconds ?? 0);
  final controller = ref.read(musicCenterControllerProvider.notifier);
  // 每日推荐按已启用平台取最近播放：传空集合会让这一栏在任何时候都不出现。
  final recentPlayables = _recentItems(center, sources);
  final dailyFirst = recentPlayables.firstOrNull;
  return SingleChildScrollView(
    padding: const EdgeInsets.only(bottom: 96),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (track != null)
          SampleNowPlayingCard(
            eyebrow: l10n.musicDeckNowPlaying,
            title: track.title,
            subtitle: track.artistName,
            imageUrl: track.coverUrl,
            progress:
                duration.inMilliseconds > 0
                    ? position.inMilliseconds / duration.inMilliseconds
                    : 0,
            progressText:
                '${_formatShortDuration(position)} / ${_formatShortDuration(duration)}',
            onTap: () => context.push('/music/now-playing'),
          ),
        if (dailyVisible && recentPlayables.isNotEmpty) ...[
          const SizedBox(height: 24),
          _SectionTitle(title: l10n.musicDailyRecommendationTitle),
          const SizedBox(height: 12),
          SampleRail(
            children: [
              for (final item in recentPlayables.take(8))
                SampleAlbumCard(
                  imageUrl: item.track.coverUrl,
                  title: item.track.title,
                  subtitle: item.track.artistName,
                  onTap: () => controller.playItems([item]),
                  onPlay: () => controller.playItems([item]),
                  showPlayOverlay: item == dailyFirst,
                ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        _SectionTitle(
          title: l10n.musicDeckYourCollections,
          actionLabel: l10n.musicViewAllSimple,
          onAction: () => onSectionChanged(MusicDeckSection.playlists),
        ),
        const SizedBox(height: 12),
        if (covers.isEmpty)
          _InlineEmpty(message: l10n.musicPlaylistsEmptyHint)
        else
          SampleRail(
            children: [
              for (final cover in covers)
                SampleAlbumCard(
                  imageUrl: cover.imageUrl,
                  title: cover.title,
                  subtitle: cover.subtitle,
                  onTap: cover.onTap,
                ),
            ],
          ),
        const SizedBox(height: 24),
        _SectionTitle(
          title: l10n.musicDeckContinueListening,
          actionLabel: l10n.musicViewAllSimple,
          // 样例 Up next 行动即 History：托管态没有 recent 分段，落历史页。
          onAction: () => unawaited(context.push('/music/history')),
        ),
        const SizedBox(height: 4),
        for (final (index, item) in recent.take(6).indexed)
          SampleSerifRow(
            number: '${index + 1}',
            title: item.track.title,
            subtitle:
                '${item.track.artistName} · ${_formatShortDuration(Duration(seconds: item.track.durationSeconds ?? 0))}',
            onTap: () => controller.playItems(recent, startIndex: index),
            trailing: Icon(
              Icons.more_horiz_rounded,
              size: 19,
              color: context.env.inkFaint,
            ),
          ),
      ],
    ),
  );
}

String _formatShortDuration(Duration d) {
  final m = d.inMinutes;
  final sec = d.inSeconds % 60;
  return '$m:${sec.toString().padLeft(2, '0')}';
}
