part of 'desktop_dock.dart';

class _QueueBody extends ConsumerWidget {
  const _QueueBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final center = ref.watch(musicCenterControllerProvider).asData?.value;
    final queue = center?.playbackItems ?? const <MusicPlayableItem>[];
    final activeIndex = center?.playbackIndex ?? -1;
    final controller = ref.read(musicCenterControllerProvider.notifier);

    if (queue.isEmpty) {
      return DesktopEmpty(
        message: l10n.desktopDockQueueEmpty,
        icon: DesktopIcons.queue,
        actionLabel: l10n.desktopOpenMusic,
        onAction: () => desktopGo(context, DesktopRoutes.music),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: DesktopEyebrow(l10n.desktopDockNowPlaying)),
            DesktopLink(
              label: l10n.desktopDockClear,
              trailing: false,
              onPressed: () async {
                final confirmed = await showDesktopConfirm(
                  context,
                  title: l10n.musicQueueClear,
                  message: l10n.desktopDockQueueClearConfirm,
                  confirmLabel: l10n.desktopDockClear,
                  cancelLabel: l10n.desktopCancel,
                  destructive: true,
                );
                if (!confirmed || !context.mounted) {
                  return;
                }
                controller.clearQueue();
                showDesktopToast(
                  context,
                  l10n.desktopToastQueueCleared,
                  icon: DesktopIcons.check,
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: queue.length,
          onReorderItem: (oldIndex, adjustedIndex) {
            // reorderQueue 沿用旧版 onReorder 的原始索引约定，
            // 后移时把已调整索引补回一位（与音乐队列面板同一适配）。
            final rawIndex =
                adjustedIndex >= oldIndex ? adjustedIndex + 1 : adjustedIndex;
            controller.reorderQueue(oldIndex, rawIndex);
          },
          proxyDecorator:
              (child, index, animation) => Material(
                color: Colors.transparent,
                child: Opacity(
                  opacity: 0.85,
                  alwaysIncludeSemantics: true,
                  child: child,
                ),
              ),
          itemBuilder: (context, index) {
            final item = queue[index];
            final track = item.track;
            final isCurrent = index == activeIndex;
            return ReorderableDragStartListener(
              key: ValueKey('desktop-queue-$index-${item.ref.playableKey}'),
              index: index,
              child: DesktopHover(
                builder:
                    (context, hovered) => GestureDetector(
                      onDoubleTap: () => controller.playQueueIndex(index),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 2),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color:
                              isCurrent
                                  ? skin.accentWash(0.12)
                                  : hovered
                                  ? skin.raise
                                  : Colors.transparent,
                          borderRadius: BorderRadius.circular(
                            DesktopMetrics.radiusButton,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              DesktopIcons.list,
                              size: 14,
                              color: hovered ? skin.text3 : Colors.transparent,
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 38,
                              height: 38,
                              child: DesktopCover(
                                url: track.listCoverUrl ?? track.coverUrl,
                                kind: DesktopCoverKind.music,
                                fallbackIcon: DesktopIcons.music,
                                borderRadius: BorderRadius.circular(7),
                                cacheKey: 'desktop-queue-${track.id}',
                                iconSize: 16,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    track.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: DesktopType.denseStrong(
                                      isCurrent ? skin.accent : skin.text,
                                    ),
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
                            if (isCurrent)
                              Icon(
                                DesktopIcons.volume,
                                size: 14,
                                color: skin.accent,
                              )
                            else
                              DesktopIconButton(
                                icon: DesktopIcons.close,
                                size: DesktopMetrics.iconButtonSmallSize,
                                iconSize: 13,
                                tooltip: l10n.desktopBookRemove,
                                onPressed:
                                    () => controller.removeFromQueue(
                                      item.ref.playableKey,
                                    ),
                              ),
                          ],
                        ),
                      ),
                    ),
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        Center(
          child: Text(
            l10n.desktopQueueHint,
            style: DesktopType.caption(skin.text3),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: DesktopLink(
            label: l10n.desktopOpenNowPlaying,
            onPressed: () => desktopPush(context, DesktopRoutes.nowPlaying),
          ),
        ),
      ],
    );
  }
}
