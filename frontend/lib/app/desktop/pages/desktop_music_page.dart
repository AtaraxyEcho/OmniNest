import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_player_bar.dart'
    show formatDesktopClock;
import 'package:omninest/app/desktop/desktop_routes.dart';
import 'package:omninest/app/desktop/desktop_shell_state.dart';
import 'package:omninest/app/desktop/desktop_toast.dart';
import 'package:omninest/app/desktop/desktop_router_scope.dart';
import 'package:omninest/app/desktop/pages/desktop_music_metadata_drawer.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_cover.dart';
import 'package:omninest/app/desktop/widgets/desktop_dialogs.dart';
import 'package:omninest/app/desktop/widgets/desktop_fields.dart';
import 'package:omninest/app/desktop/widgets/desktop_glass.dart';
import 'package:omninest/app/desktop/widgets/desktop_pager.dart';
import 'package:omninest/app/desktop/widgets/desktop_select.dart';
import 'package:omninest/app/desktop/widgets/desktop_surfaces.dart';
import 'package:omninest/app/desktop/widgets/desktop_track_hue.dart';
import 'package:omninest/app/desktop/widgets/desktop_tilt.dart';
import 'package:omninest/app/desktop/widgets/desktop_visualizer.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
// 不带 show 白名单：控制器动作是**无名扩展**，show 会把它们一并滤掉。
import 'package:omninest/features/music/music_portal.dart';

// 页面骨架、主视觉和曲目行分开放置，以职责拆分满足单文件长度守卫。
part 'desktop_music_widgets.dart';
part 'desktop_music_rows.dart';

/// 桌面音乐页（样例 `Music.tsx` 的 Home/Tracks/Albums）。
///
/// 与移动端的「玻璃卡组」是两套形态：桌面按样例走「当前播放主视觉 +
/// 曲目表」——主视觉承担播放器身份，表格承担检索。
enum DesktopMusicTab { home, tracks, albums, playlists, favorites }

class DesktopMusicPage extends ConsumerStatefulWidget {
  const DesktopMusicPage({super.key});

  @override
  ConsumerState<DesktopMusicPage> createState() => _DesktopMusicPageState();
}

class _DesktopMusicPageState extends ConsumerState<DesktopMusicPage> {
  DesktopMusicTab _tab = DesktopMusicTab.home;
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _openPlaylist(MusicPlaylist playlist) async {
    final l10n = AppLocalizations.of(context);
    try {
      await ref
          .read(musicCenterControllerProvider.notifier)
          .openPlaylist(playlist);
    } on Object catch (error) {
      if (mounted) {
        showDesktopToast(
          context,
          failureToast(l10n, l10n.musicOpenPlaylist, error),
          kind: DesktopToastKind.error,
          icon: DesktopIcons.info,
        );
      }
    }
  }

  Future<void> _playSelectedPlaylist({bool shuffle = false}) async {
    final current = ref.read(musicCenterControllerProvider).asData?.value;
    final playlist = current?.selectedPlaylist;
    if (playlist == null) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(musicCenterControllerProvider.notifier);
    try {
      final tracks = await controller.ensureCompletePlaylistTracks();
      if (!mounted || tracks.isEmpty) {
        return;
      }
      final ordered = tracks.toList(growable: true);
      if (shuffle) {
        ordered.shuffle();
      }
      await controller.playItems(
        ordered.map(MusicPlayableItem.local).toList(growable: false),
      );
    } on Object catch (error) {
      if (mounted) {
        showDesktopToast(
          context,
          failureToast(l10n, l10n.musicPlay, error),
          kind: DesktopToastKind.error,
          icon: DesktopIcons.info,
        );
      }
    }
  }

  Future<void> _addSelectedPlaylistToQueue() async {
    final current = ref.read(musicCenterControllerProvider).asData?.value;
    final playlist = current?.selectedPlaylist;
    if (playlist == null) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(musicCenterControllerProvider.notifier);
    try {
      final tracks = await controller.ensureCompletePlaylistTracks();
      if (!mounted) {
        return;
      }
      if (tracks.isEmpty) {
        return;
      }
      for (final track in tracks) {
        controller.enqueue(MusicPlayableItem.local(track));
      }
      showDesktopToast(
        context,
        l10n.musicPlayNextAdded,
        icon: DesktopIcons.queue,
      );
    } on Object catch (error) {
      if (mounted) {
        showDesktopToast(
          context,
          failureToast(l10n, l10n.musicAddToQueue, error),
          kind: DesktopToastKind.error,
          icon: DesktopIcons.info,
        );
      }
    }
  }

  Future<void> _editPlaylist({MusicPlaylist? playlist}) async {
    final l10n = AppLocalizations.of(context);
    final taken =
        ref
            .read(musicCenterControllerProvider)
            .asData
            ?.value
            .playlists
            .where((item) => item.id != playlist?.id)
            .map((item) => item.name.toLowerCase())
            .toSet() ??
        const <String>{};
    final result = await showDesktopDrawer<(String, String)>(
      context,
      width: 440,
      builder: (_) => _PlaylistEditor(playlist: playlist, takenNames: taken),
    );
    if (result == null || !mounted) {
      return;
    }
    final controller = ref.read(musicCenterControllerProvider.notifier);
    try {
      if (playlist == null) {
        await controller.createPlaylist(
          name: result.$1,
          description: result.$2.isEmpty ? null : result.$2,
        );
      } else {
        await controller.updatePlaylist(
          playlist,
          name: result.$1,
          description: result.$2.isEmpty ? null : result.$2,
        );
      }
      if (mounted) {
        showDesktopToast(
          context,
          playlist == null ? l10n.musicCreatePlaylist : l10n.musicMetadataSaved,
          icon: DesktopIcons.check,
        );
      }
    } on Object catch (error) {
      if (mounted) {
        showDesktopToast(
          context,
          failureToast(
            l10n,
            playlist == null
                ? l10n.musicCreatePlaylist
                : l10n.musicEditPlaylist,
            error,
          ),
          kind: DesktopToastKind.error,
          icon: DesktopIcons.info,
        );
      }
    }
  }

  Future<void> _deletePlaylist(MusicPlaylist playlist) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDesktopDialog<bool>(
      context,
      builder:
          (dialogContext) => DesktopDialog(
            eyebrow: l10n.musicDeckPlaylists,
            title: l10n.musicDeletePlaylistTitle,
            content: Text(
              l10n.musicDeletePlaylistMessage(playlist.name),
              style: DesktopType.dense(DesktopSkin.of(dialogContext).text2),
            ),
            actions: [
              DesktopButton(
                label: l10n.filesCancel,
                onPressed: () => closeDesktopModal(dialogContext, false),
              ),
              DesktopButton(
                label: l10n.musicDeletePlaylist,
                icon: DesktopIcons.trash,
                variant: DesktopButtonVariant.danger,
                onPressed: () => closeDesktopModal(dialogContext, true),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await ref
          .read(musicCenterControllerProvider.notifier)
          .deletePlaylist(playlist);
    } on Object catch (error) {
      if (mounted) {
        showDesktopToast(
          context,
          failureToast(l10n, l10n.musicDeletePlaylist, error),
          kind: DesktopToastKind.error,
          icon: DesktopIcons.info,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(musicCenterControllerProvider).asData?.value;
    final actions = ref.watch(musicPortalActionsProvider);
    final selectedPlaylist =
        state?.section == MusicSection.playlistDetail
            ? state?.selectedPlaylist
            : null;

    final labels = <DesktopMusicTab, String>{
      DesktopMusicTab.home: l10n.desktopNavHome,
      DesktopMusicTab.tracks: l10n.desktopMusicTracks,
      DesktopMusicTab.albums: l10n.photosTabAlbums,
      DesktopMusicTab.playlists: l10n.musicDeckPlaylists,
      DesktopMusicTab.favorites: l10n.photosFavorite,
    };

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (selectedPlaylist != null &&
            notification.metrics.extentAfter < 320 &&
            state?.detailPaging.hasMore == true &&
            state?.detailPaging.loadingMore != true) {
          unawaited(
            ref
                .read(musicCenterControllerProvider.notifier)
                .loadMorePlaylistTracks(),
          );
        }
        return false;
      },
      child: SingleChildScrollView(
        child: DesktopPage(
          topPadding: DesktopMetrics.pageTopPaddingCompact,
          children: [
            if (selectedPlaylist != null)
              _PlaylistDetail(
                playlist: selectedPlaylist,
                tracks: state?.selectedPlaylistTracks ?? const <MusicTrack>[],
                loadingMore: state?.detailPaging.loadingMore ?? false,
                currentId: state?.currentItem?.track.id,
                playing: state?.isPlaying ?? false,
                onBack:
                    () =>
                        ref
                            .read(musicCenterControllerProvider.notifier)
                            .closePlaylist(),
                onPlay: () => _playSelectedPlaylist(),
                onShuffle: () => _playSelectedPlaylist(shuffle: true),
                onAddToQueue: _addSelectedPlaylistToQueue,
                onEdit: () => _editPlaylist(playlist: selectedPlaylist),
                onDelete: () => _deletePlaylist(selectedPlaylist),
                onTrackPlay: (track) => actions.playTrackById(track.id),
              )
            else ...[
              DesktopPageHead(
                eyebrow:
                    l10n
                        .desktopMusicHeadline(
                          state?.tracks.length ?? 0,
                          state?.albums.length ?? 0,
                        )
                        .toUpperCase(),
                title: l10n.desktopNavMusic,
                actions: [
                  DesktopSeg<DesktopMusicTab>(
                    options: DesktopMusicTab.values,
                    value: _tab,
                    labelOf: (value) => labels[value] ?? '',
                    onChanged: (value) => setState(() => _tab = value),
                  ),
                ],
              ),
              switch (_tab) {
                DesktopMusicTab.home => _Home(
                  state: state,
                  playlists: state?.playlists ?? const <MusicPlaylist>[],
                  onSeeAlbums:
                      () => setState(() => _tab = DesktopMusicTab.albums),
                  onPlayPlaylist: _openPlaylist,
                  onSeePlaylists:
                      () => setState(() => _tab = DesktopMusicTab.playlists),
                  onTogglePlayback: () => actions.togglePlayback(),
                  onOpenQueue:
                      () => ref
                          .read(desktopShellProvider.notifier)
                          .setDockTab(DesktopDockTab.queue),
                  onPlayQueueItem:
                      (index) => actions.playQueueAt(index).ignore(),
                ),
                DesktopMusicTab.playlists => _PlaylistGrid(
                  playlists: state?.playlists ?? const <MusicPlaylist>[],
                  onOpen: _openPlaylist,
                  onCreate: () => _editPlaylist(),
                ),
                DesktopMusicTab.tracks => _TracksView(
                  tracks: state?.tracks ?? const [],
                  search: _search,
                  onPlay: (track) => actions.playTrackById(track.id),
                  currentId: state?.currentItem?.playableKey,
                  playing: state?.isPlaying ?? false,
                ),
                DesktopMusicTab.favorites => _TracksView(
                  tracks:
                      state?.tracks
                          .where((track) => track.favorite)
                          .toList(growable: false) ??
                      const <MusicTrack>[],
                  search: _search,
                  onPlay: (track) => actions.playTrackById(track.id),
                  currentId: state?.currentItem?.playableKey,
                  playing: state?.isPlaying ?? false,
                  showControls: false,
                ),
                DesktopMusicTab.albums => _AlbumGrid(
                  albums: state?.albums ?? const [],
                  emptyLabel: l10n.musicNoAlbums,
                ),
              },
            ],
          ],
        ),
      ),
    );
  }
}

class _Home extends StatelessWidget {
  const _Home({
    required this.state,
    required this.playlists,
    required this.onSeeAlbums,
    required this.onPlayPlaylist,
    required this.onSeePlaylists,
    required this.onTogglePlayback,
    required this.onOpenQueue,
    required this.onPlayQueueItem,
  });

  final MusicCenterState? state;
  final List<MusicPlaylist> playlists;
  final VoidCallback onSeeAlbums;
  final ValueChanged<MusicPlaylist> onPlayPlaylist;
  final VoidCallback onSeePlaylists;
  final VoidCallback onTogglePlayback;
  final VoidCallback onOpenQueue;
  final ValueChanged<int> onPlayQueueItem;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final album = state?.albums.take(8).toList() ?? const <MusicAlbum>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FocusHero(state: state, onTogglePlayback: onTogglePlayback),
        DesktopSection(
          eyebrow: l10n.desktopRecentlyAdded,
          title: l10n.photosTabAlbums,
          actionLabel: l10n.desktopSeeAllCount(state?.albums.length ?? 0),
          onAction: onSeeAlbums,
          child: _AlbumRail(albums: album),
        ),
        DesktopSection(
          eyebrow: l10n.desktopMusicLibraryEyebrow,
          title: l10n.musicDeckPlaylists,
          actionLabel: l10n.desktopSeeAllCount(playlists.length),
          onAction: onSeePlaylists,
          child: _PlaylistRail(
            playlists: playlists.take(8).toList(growable: false),
            onPlay: onPlayPlaylist,
          ),
        ),
        DesktopSection(
          title: l10n.desktopUpNext,
          actionLabel: l10n.desktopOpenQueue,
          onAction: onOpenQueue,
          child: _QueueRows(state: state, onPlayAt: onPlayQueueItem),
        ),
      ],
    );
  }
}
