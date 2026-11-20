import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_player_bar.dart'
    show formatDesktopClock;
import 'package:omninest/app/desktop/desktop_routes.dart';
import 'package:omninest/app/desktop/desktop_shell_state.dart';
import 'package:omninest/app/desktop/desktop_toast.dart';
import 'package:omninest/app/session/session_epoch.dart';
import 'package:omninest/app/desktop/desktop_router_scope.dart';
import 'package:omninest/app/desktop/pages/desktop_music_metadata_drawer.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_cover.dart';
import 'package:omninest/app/desktop/widgets/desktop_dialogs.dart';
import 'package:omninest/app/desktop/widgets/desktop_error_view.dart';
import 'package:omninest/app/desktop/widgets/desktop_fields.dart';
import 'package:omninest/app/desktop/widgets/desktop_media_import_dialog.dart'
    show
        DesktopMediaImportKind,
        DesktopMediaImportSelection,
        showDesktopMediaImportDialog;
import 'package:omninest/app/desktop/widgets/desktop_glass.dart';
import 'package:omninest/app/desktop/widgets/desktop_pager.dart';
import 'package:omninest/app/desktop/widgets/desktop_skeleton.dart';
import 'package:omninest/app/desktop/widgets/desktop_select.dart';
import 'package:omninest/app/desktop/widgets/desktop_surfaces.dart';
import 'package:omninest/app/desktop/widgets/desktop_track_hue.dart';
import 'package:omninest/app/desktop/widgets/desktop_visualizer.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
// 不带 show 白名单：控制器动作是**无名扩展**，show 会把它们一并滤掉。
import 'package:omninest/features/files/media_import_ui.dart'
    show MediaImportButton, MediaImportButtonState;
import 'package:omninest/features/files/application/file_browser_controller.dart';
import 'package:omninest/features/files/application/media_import_queue_controller.dart';
import 'package:omninest/features/files/application/media_import_service.dart'
    show MediaImportBatchResult;
import 'package:omninest/features/music/application/music_scan_job_controller.dart';
import 'package:omninest/features/music/application/music_platform_library_controller.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/music_portal.dart';
import 'package:omninest/features/video/application/media_import_task_waiter.dart';

// 页面骨架、主视觉和曲目行分开放置，以职责拆分满足单文件长度守卫。
part 'desktop_music_widgets.dart';
part 'desktop_music_rows.dart';
part 'desktop_music_loading.dart';
part 'desktop_music_album_detail.dart';
part 'desktop_music_platform.dart';

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
  MusicAlbum? _selectedAlbum;
  final TextEditingController _search = TextEditingController();
  final GlobalKey<MediaImportButtonState> _mediaImportKey =
      GlobalKey<MediaImportButtonState>();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Widget _importAction(BuildContext context, AppLocalizations l10n) {
    final appContainer = ProviderScope.containerOf(context, listen: false);
    bool isCurrentSession(int epoch) =>
        appContainer.read(sessionEpochProvider) == epoch;

    Future<void> completeImport(
      MediaImportBatchResult result, {
      required int sessionEpoch,
    }) async {
      if (result.imported.isEmpty || !isCurrentSession(sessionEpoch)) return;
      final taskWaiter = appContainer.read(mediaImportTaskWaiterProvider);
      for (final file in result.imported) {
        if (!isCurrentSession(sessionEpoch)) return;
        final taskId = file.mediaAutoImportTaskId;
        if (taskId == null || taskId.isEmpty) continue;
        try {
          await taskWaiter.waitForTerminal(taskId);
        } on Object catch (error) {
          if (isCurrentSession(sessionEpoch) && mounted && context.mounted) {
            showDesktopToast(
              context,
              failureToast(l10n, l10n.filesImport, error),
              kind: DesktopToastKind.warn,
            );
          }
        }
        if (!isCurrentSession(sessionEpoch)) return;
      }
      if (!isCurrentSession(sessionEpoch)) return;
      await appContainer
          .read(musicScanJobControllerProvider.notifier)
          .startScan();
      if (!isCurrentSession(sessionEpoch)) return;
      await appContainer.read(musicCenterControllerProvider.notifier).refresh();
    }

    return MediaImportButton(
      key: _mediaImportKey,
      subsystemDirectory: 'Music',
      allowSharedSpace: false,
      acceptedExtensions: const <String>[
        'mp3',
        'flac',
        'aac',
        'm4a',
        'ogg',
        'opus',
        'wav',
        'wma',
      ],
      label: l10n.filesImport,
      onPressedOverride: () => unawaited(_openImportDialog(context, l10n)),
      buttonBuilder:
          (context, {required onPressed, required busy}) => DesktopButton(
            label: l10n.filesImport,
            icon: DesktopIcons.download,
            variant: DesktopButtonVariant.soft,
            onPressed: onPressed,
            busy: busy,
          ),
      onFilesPicked: (files, spaceType) {
        final importSessionEpoch = appContainer.read(sessionEpochProvider);
        ref
            .read(mediaImportQueueProvider.notifier)
            .enqueue(
              files: files,
              directoryName: 'Music',
              spaceType: spaceType,
              reuseExistingFiles: false,
              titleForFile:
                  (file) =>
                      '${l10n.desktopMediaImportTaskMusic} · ${file.name}',
              onComplete: (result) async {
                await completeImport(result, sessionEpoch: importSessionEpoch);
                if (!isCurrentSession(importSessionEpoch) ||
                    !mounted ||
                    !context.mounted) {
                  return;
                }
                if (result.failures.isEmpty) {
                  showDesktopToast(
                    context,
                    l10n.importComplete(result.imported.length),
                    icon: DesktopIcons.check,
                  );
                } else {
                  showDesktopToast(
                    context,
                    l10n.importFailed,
                    kind: DesktopToastKind.warn,
                  );
                }
              },
            );
        showDesktopToast(
          context,
          l10n.desktopMediaImportQueued(files.length),
          icon: DesktopIcons.download,
          actionLabel: l10n.desktopViewTasks,
          onAction:
              () => appContainer
                  .read(desktopShellProvider.notifier)
                  .setPanel(DesktopPanel.tasks),
        );
      },
      onImportComplete: () async {
        await appContainer
            .read(musicScanJobControllerProvider.notifier)
            .startScan();
        if (!context.mounted) return;
        await appContainer
            .read(musicCenterControllerProvider.notifier)
            .refresh();
      },
    );
  }

  Future<void> _openImportDialog(
    BuildContext context,
    AppLocalizations l10n,
  ) async {
    final selection = await showDesktopMediaImportDialog(
      context,
      kind: DesktopMediaImportKind.music,
    );
    if (!mounted || !context.mounted || selection == null) return;
    if (selection.deviceFiles.isNotEmpty) {
      await _mediaImportKey.currentState?.importFiles(selection.deviceFiles);
      return;
    }
    if (selection.fileNodeIds.isNotEmpty) {
      await _importExistingFiles(context, l10n, selection);
    }
  }

  Future<void> _importExistingFiles(
    BuildContext context,
    AppLocalizations l10n,
    DesktopMediaImportSelection selection,
  ) async {
    try {
      final tasks = await ref
          .read(fileBrowserControllerProvider.notifier)
          .requestMediaImports(
            fileNodeIds: selection.fileNodeIds,
            mediaType: 'MUSIC',
          );
      if (!mounted || !context.mounted) return;
      showDesktopToast(
        context,
        l10n.importProcessing(tasks.length),
        kind: DesktopToastKind.info,
      );
      final taskWaiter = ref.read(mediaImportTaskWaiterProvider);
      for (final task in tasks) {
        try {
          await taskWaiter.waitForTerminal(task.taskId);
        } on Object catch (error) {
          if (!mounted || !context.mounted) return;
          showDesktopToast(
            context,
            failureToast(l10n, l10n.filesImport, error),
            kind: DesktopToastKind.warn,
          );
        }
        if (!mounted || !context.mounted) return;
      }
      await ref.read(musicCenterControllerProvider.notifier).refresh();
    } on Object catch (error) {
      if (!mounted || !context.mounted) return;
      showDesktopToast(
        context,
        failureToast(l10n, l10n.filesImport, error),
        kind: DesktopToastKind.error,
      );
    }
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
    final musicAsync = ref.watch(musicCenterControllerProvider);
    final state = musicAsync.asData?.value;
    final platformAsync = ref.watch(musicPlatformLibraryProvider);
    final platform =
        platformAsync.asData?.value ?? const MusicPlatformLibraryState();
    final actions = ref.watch(musicPortalActionsProvider);
    final selectedPlaylist =
        state?.section == MusicSection.playlistDetail
            ? state?.selectedPlaylist
            : null;
    final selectedAlbum = _selectedAlbum;
    final albumTracks =
        selectedAlbum == null
            ? const <MusicTrack>[]
            : (state?.tracks ?? const <MusicTrack>[])
                .where((track) => track.albumTitle == selectedAlbum.title)
                .toList(growable: false);
    Widget initialContent() =>
        musicAsync.hasError
            ? DesktopErrorView(
              message: errorReason(musicAsync.error!, l10n),
              onRetry: () => ref.invalidate(musicCenterControllerProvider),
            )
            : _MusicLoadingSkeleton(tab: _tab);

    final labels = <DesktopMusicTab, String>{
      DesktopMusicTab.home: l10n.desktopNavHome,
      DesktopMusicTab.tracks: l10n.desktopMusicTracks,
      // 音乐专辑/歌单必须走音乐模块本地化键；误用照片模块的「相册」标签
      // 会让 Music 页出现一个并不存在的相册栏。
      DesktopMusicTab.albums: l10n.musicNavAlbums,
      DesktopMusicTab.playlists: l10n.musicNavPlaylists,
      DesktopMusicTab.favorites: l10n.musicNavFavorites,
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
            if (selectedAlbum != null)
              _AlbumDetail(
                album: selectedAlbum,
                tracks: albumTracks,
                currentId: state?.currentItem?.playableKey,
                playing: state?.isPlaying ?? false,
                onBack: () => setState(() => _selectedAlbum = null),
                onPlay: () => _playAlbumTracks(albumTracks),
                onShuffle: () => _playAlbumTracks(albumTracks, shuffle: true),
                onAddToQueue: () => _enqueueAlbumTracks(albumTracks),
                onTrackPlay: (track) => actions.playTrackById(track.id),
              )
            else if (selectedPlaylist != null)
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
                  _importAction(context, l10n),
                  DesktopSeg<DesktopMusicTab>(
                    options: DesktopMusicTab.values,
                    value: _tab,
                    labelOf: (value) => labels[value] ?? '',
                    onChanged:
                        (value) => setState(() {
                          _tab = value;
                          _selectedAlbum = null;
                        }),
                  ),
                ],
              ),
              switch (_tab) {
                DesktopMusicTab.home when state == null => initialContent(),
                DesktopMusicTab.home => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Home(
                      state: state,
                      playlists: state?.playlists ?? const <MusicPlaylist>[],
                      onSeeAlbums:
                          () => setState(() => _tab = DesktopMusicTab.albums),
                      onOpenAlbum:
                          (album) => setState(() => _selectedAlbum = album),
                      onPlayPlaylist: _openPlaylist,
                      onSeePlaylists:
                          () =>
                              setState(() => _tab = DesktopMusicTab.playlists),
                      onTogglePlayback: () => actions.togglePlayback(),
                      onOpenQueue:
                          () => ref
                              .read(desktopShellProvider.notifier)
                              .setDockTab(DesktopDockTab.queue),
                      onPlayQueueItem:
                          (index) => actions.playQueueAt(index).ignore(),
                    ),
                    if (platform.playlists.isNotEmpty)
                      _DesktopOnlinePlaylistSection(
                        library: platform,
                        playlists: platform.playlists,
                        onOpen:
                            (playlist) =>
                                _playOnlinePlaylist(playlist).ignore(),
                      ),
                    if (platform.likedTracks.isNotEmpty)
                      _DesktopOnlineTrackSection(
                        tracks: platform.likedTracks,
                        currentId: state?.currentItem?.playableKey,
                        playing: state?.isPlaying ?? false,
                        onPlay:
                            (track) =>
                                ref
                                    .read(
                                      musicCenterControllerProvider.notifier,
                                    )
                                    .playOnlineTrack(track)
                                    .ignore(),
                      ),
                  ],
                ),
                DesktopMusicTab.playlists when state == null =>
                  initialContent(),
                DesktopMusicTab.playlists => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _PlaylistGrid(
                      playlists: state?.playlists ?? const <MusicPlaylist>[],
                      onOpen: _openPlaylist,
                      onCreate: () => _editPlaylist(),
                    ),
                    if (platform.playlists.isNotEmpty)
                      _DesktopOnlinePlaylistSection(
                        library: platform,
                        playlists: platform.playlists,
                        onOpen:
                            (playlist) =>
                                _playOnlinePlaylist(playlist).ignore(),
                      ),
                  ],
                ),
                DesktopMusicTab.tracks when state == null => initialContent(),
                DesktopMusicTab.tracks => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TracksView(
                      tracks: state?.tracks ?? const [],
                      search: _search,
                      onPlay: (track) => actions.playTrackById(track.id),
                      currentId: state?.currentItem?.playableKey,
                      playing: state?.isPlaying ?? false,
                    ),
                    if (platform.likedTracks.isNotEmpty)
                      _DesktopOnlineTrackSection(
                        tracks: platform.likedTracks,
                        currentId: state?.currentItem?.playableKey,
                        playing: state?.isPlaying ?? false,
                        onPlay:
                            (track) =>
                                ref
                                    .read(
                                      musicCenterControllerProvider.notifier,
                                    )
                                    .playOnlineTrack(track)
                                    .ignore(),
                      ),
                  ],
                ),
                DesktopMusicTab.favorites when state == null =>
                  initialContent(),
                DesktopMusicTab.favorites => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TracksView(
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
                    if (platform.likedTracks.isNotEmpty)
                      _DesktopOnlineTrackSection(
                        tracks: platform.likedTracks,
                        currentId: state?.currentItem?.playableKey,
                        playing: state?.isPlaying ?? false,
                        onPlay:
                            (track) =>
                                ref
                                    .read(
                                      musicCenterControllerProvider.notifier,
                                    )
                                    .playOnlineTrack(track)
                                    .ignore(),
                      ),
                  ],
                ),
                DesktopMusicTab.albums when state == null => initialContent(),
                DesktopMusicTab.albums => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _AlbumGrid(
                      albums: state?.albums ?? const [],
                      emptyLabel: l10n.musicNoAlbums,
                      onOpen: (album) => setState(() => _selectedAlbum = album),
                    ),
                    if (_knownPlatformTracks(platform).isNotEmpty)
                      _DesktopOnlineAlbumSection(
                        tracks: _knownPlatformTracks(platform),
                        currentId: state?.currentItem?.playableKey,
                        playing: state?.isPlaying ?? false,
                        onPlay: _playOnlineTracks,
                      ),
                  ],
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
    required this.onOpenAlbum,
    required this.onPlayPlaylist,
    required this.onSeePlaylists,
    required this.onTogglePlayback,
    required this.onOpenQueue,
    required this.onPlayQueueItem,
  });

  final MusicCenterState? state;
  final List<MusicPlaylist> playlists;
  final VoidCallback onSeeAlbums;
  final ValueChanged<MusicAlbum> onOpenAlbum;
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
          title: l10n.musicNavAlbums,
          actionLabel: l10n.desktopSeeAllCount(state?.albums.length ?? 0),
          onAction: onSeeAlbums,
          child: _AlbumRail(albums: album, onOpen: onOpenAlbum),
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
