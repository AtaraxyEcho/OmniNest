import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/music_colors.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';
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
      heightFactor: 0.72,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: MusicDeckGlass(
            opacity: 0.42,
            blur: 20,
            borderRadius: 14,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                // 拖拽把手
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 2),
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.musicColors.onSurfaceVariant.withValues(
                        alpha: 0.35,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 12, 0),
                  child: Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.of(context).musicQueueTitle,
                            style: TextStyle(
                              color: context.musicColors.onSurface,
                              fontSize: AppTypography.titleMedium,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            AppLocalizations.of(
                              context,
                            ).musicDeckTrackCount(items.length),
                            style: TextStyle(
                              color: context.musicColors.onSurfaceVariant,
                              fontSize: AppTypography.labelSmall,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed:
                            items.isEmpty
                                ? null
                                : () =>
                                    ref
                                        .read(
                                          musicCenterControllerProvider
                                              .notifier,
                                        )
                                        .clearQueue(),
                        icon: const Icon(Icons.delete_sweep_rounded, size: 16),
                        label: Text(
                          AppLocalizations.of(context).musicQueueClear,
                          style: const TextStyle(
                            fontSize: AppTypography.bodySmall,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: AppLocalizations.of(context).musicClose,
                        visualDensity: VisualDensity.compact,
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded, size: 19),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Divider(color: context.musicColors.outline, height: 1),
                ),
                Expanded(
                  child:
                      items.isEmpty
                          ? Center(
                            child: Text(
                              AppLocalizations.of(context).musicQueueEmpty,
                              style: TextStyle(
                                color: context.musicColors.onSurfaceVariant,
                                fontSize: AppTypography.bodyMedium,
                              ),
                            ),
                          )
                          : ReorderableListView.builder(
                            itemExtent: 62,
                            padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
                            buildDefaultDragHandles: false,
                            onReorderItem: (oldIndex, adjustedIndex) {
                              debugPrint('[QueueSheet] onReorderItem($oldIndex,$adjustedIndex)');
                              // reorderQueue 沿用旧版 onReorder 的原始索引约定，
                              // 后移时把已调整索引补回一位。
                              final rawIndex =
                                  adjustedIndex >= oldIndex
                                      ? adjustedIndex + 1
                                      : adjustedIndex;
                              ref
                                  .read(musicCenterControllerProvider.notifier)
                                  .reorderQueue(oldIndex, rawIndex);
                            },
                            itemCount: items.length,
                            itemBuilder: (context, index) {
                              final item = items[index];
                              final selected =
                                  item.playableKey ==
                                  music?.currentItem?.playableKey;
                              return _MusicQueueRow(
                                key: ValueKey<String>(item.playableKey),
                                item: item,
                                index: index,
                                selected: selected,
                                onTap: () {
                                  ref
                                      .read(
                                        musicCenterControllerProvider.notifier,
                                      )
                                      .playItems(items, startIndex: index);
                                },
                                onDismissed:
                                    () => ref
                                        .read(
                                          musicCenterControllerProvider
                                              .notifier,
                                        )
                                        .removeFromQueue(item.playableKey),
                              );
                            },
                          ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MusicQueueRow extends StatelessWidget {
  const _MusicQueueRow({
    required this.item,
    required this.index,
    required this.selected,
    required this.onTap,
    required this.onDismissed,
    super.key,
  });

  final MusicPlayableItem item;
  final int index;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDismissed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.musicColors;
    return Dismissible(
      key: ValueKey<String>('queue-dismiss-${item.playableKey}'),
      direction: DismissDirection.endToStart,
      background: _MusicQueueDismissBackground(
        color: Theme.of(context).colorScheme.errorContainer,
        iconColor: Theme.of(context).colorScheme.onErrorContainer,
      ),
      onDismissed: (_) => onDismissed(),
      child: ListTile(
        selected: selected,
        selectedTileColor: colors.selectedBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        onTap: onTap,
        leading: SizedBox.square(
          dimension: 42,
          child: MusicDeckArtwork(
            title: item.track.title,
            imageUrl: item.track.coverUrl,
            borderRadius: 6,
          ),
        ),
        title: Text(
          item.track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: selected ? colors.primary : colors.onSurface,
            fontSize: AppTypography.bodyMedium,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            item.track.artistName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontSize: AppTypography.labelSmall,
            ),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected)
              Icon(Icons.graphic_eq_rounded, size: 16, color: colors.primary),
            ReorderableDragStartListener(
              index: index,
              child: Semantics(
                label: l10n.musicQueueReorderHint,
                button: true,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    Icons.drag_indicator_rounded,
                    size: 18,
                    color: colors.onSurfaceVariant.withValues(alpha: 0.75),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MusicQueueDismissBackground extends StatelessWidget {
  const _MusicQueueDismissBackground({
    required this.color,
    required this.iconColor,
  });

  final Color color;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        width: 64,
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.delete_outline_rounded, size: 20, color: iconColor),
      ),
    );
  }
}
