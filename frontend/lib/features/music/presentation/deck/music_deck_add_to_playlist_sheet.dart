import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/music_colors.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_create_playlist_dialog.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_primitives.dart';

/// 弹出歌单选择抽屉，把曲目加入所选歌单或先新建歌单。
Future<void> showMusicAddToPlaylistSheet(
  BuildContext context,
  WidgetRef ref,
  MusicPlayableItem item,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder:
        (sheetContext) => MusicDeckAddToPlaylistSheet(
          item: item,
          onDismissed: () => Navigator.of(sheetContext).maybePop(),
        ),
  );
}

class MusicDeckAddToPlaylistSheet extends ConsumerWidget {
  const MusicDeckAddToPlaylistSheet({
    required this.item,
    required this.onDismissed,
    super.key,
  });

  final MusicPlayableItem item;
  final VoidCallback onDismissed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final playlists =
        ref.watch(musicCenterControllerProvider).asData?.value.playlists ??
        const <MusicPlaylist>[];
    return FractionallySizedBox(
      heightFactor: 0.6,
      child: MusicDeckGlass(
        opacity: 0.42,
        blur: 20,
        borderRadius: 8,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.musicAddToPlaylist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.musicColors.onSurface,
                      fontSize: AppTypography.titleLarge,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: l10n.musicClose,
                  onPressed: onDismissed,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            Divider(color: context.musicColors.outline),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 12),
                children: [
                  for (final playlist in playlists)
                    ListTile(
                      leading: SizedBox.square(
                        dimension: 40,
                        child: MusicDeckArtwork(
                          title: playlist.name,
                          imageUrl: playlist.coverUrl,
                          borderRadius: 5,
                        ),
                      ),
                      title: Text(
                        playlist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        l10n.musicDeckTrackCount(playlist.trackCount),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => _addToExisting(context, ref, playlist),
                    ),
                  ListTile(
                    leading: Icon(
                      Icons.add_rounded,
                      color: context.musicColors.primary,
                    ),
                    title: Text(l10n.musicCreatePlaylist),
                    onTap: () => _createAndAdd(context, ref),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addToExisting(
    BuildContext context,
    WidgetRef ref,
    MusicPlaylist playlist,
  ) async {
    onDismissed();
    await _addAndReport(context, ref, playlist);
  }

  Future<void> _createAndAdd(BuildContext context, WidgetRef ref) async {
    final draft = await showDialog<MusicDeckPlaylistDraft>(
      context: context,
      builder: (dialogContext) => const MusicDeckCreatePlaylistDialog(),
    );
    if (draft == null) {
      return;
    }
    try {
      final playlist = await ref
          .read(musicCenterControllerProvider.notifier)
          .createPlaylist(
            name: draft.name,
            description: draft.description,
            coverBytes: draft.coverBytes,
            coverFileName: draft.coverFileName,
          );
      if (playlist != null && context.mounted) {
        await _addAndReport(context, ref, playlist);
      }
    } on Exception catch (error) {
      if (context.mounted) {
        _reportFailure(context, error);
      }
    }
  }

  Future<void> _addAndReport(
    BuildContext context,
    WidgetRef ref,
    MusicPlaylist playlist,
  ) async {
    try {
      await ref
          .read(musicCenterControllerProvider.notifier)
          .addTrackToPlaylist(playlist, item.track);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(
                  context,
                ).musicAddToPlaylistSuccess(playlist.name),
              ),
            ),
          );
      }
    } on Exception catch (error) {
      if (context.mounted) {
        _reportFailure(context, error);
      }
    }
  }

  void _reportFailure(BuildContext context, Object error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).musicAddToPlaylistFailed,
            ),
          ),
        );
    }
  }
}
