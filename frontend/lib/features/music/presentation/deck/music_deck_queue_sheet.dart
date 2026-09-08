import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/music_colors.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_primitives.dart';

/// 显示当前播放队列的响应式抽屉。
Future<void> showMusicDeckQueue(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const MusicDeckQueueSheet(),
  );
}

class MusicDeckQueueSheet extends ConsumerWidget {
  const MusicDeckQueueSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final music = ref.watch(musicCenterControllerProvider).asData?.value;
    final items = music?.playbackItems ?? const [];
    return FractionallySizedBox(
      heightFactor: 0.74,
      child: MusicDeckGlass(
        opacity: 0.42,
        blur: 20,
        borderRadius: 8,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  AppLocalizations.of(context).musicQueueTitle,
                  style: TextStyle(
                    color: context.musicColors.onSurface,
                    fontSize: AppTypography.titleLarge,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: AppLocalizations.of(context).musicClose,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            Divider(color: context.musicColors.outline),
            Expanded(
              child:
                  items.isEmpty
                      ? Center(
                        child: Text(
                          AppLocalizations.of(context).musicQueueEmpty,
                          style: TextStyle(
                            color: context.musicColors.onSurfaceVariant,
                          ),
                        ),
                      )
                      : ListView.builder(
                        itemCount: items.length,
                        itemExtent: 58,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final selected =
                              item.playableKey ==
                              music?.currentItem?.playableKey;
                          return ListTile(
                            selected: selected,
                            selectedTileColor: context.musicColors.selectedBg,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                            onTap: () {
                              ref
                                  .read(musicCenterControllerProvider.notifier)
                                  .playItems(items, startIndex: index);
                            },
                            leading: SizedBox.square(
                              dimension: 40,
                              child: MusicDeckArtwork(
                                title: item.track.title,
                                imageUrl: item.track.coverUrl,
                              ),
                            ),
                            title: Text(
                              item.track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              item.track.artistName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing:
                                selected
                                    ? const Icon(Icons.graphic_eq_rounded)
                                    : null,
                          );
                        },
                      ),
            ),
          ],
        ),
      ),
    );
  }
}
