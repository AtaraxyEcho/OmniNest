import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_router_scope.dart';
import 'package:omninest/app/desktop/desktop_routes.dart';
import 'package:omninest/app/desktop/desktop_shell_state.dart';
import 'package:omninest/app/desktop/desktop_toast.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_cover.dart';
import 'package:omninest/app/desktop/widgets/desktop_glass.dart';
import 'package:omninest/app/desktop/widgets/desktop_surfaces.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/features/music/music_portal.dart';

/// 右侧详情坞（样例 `.dock`）：348px，两个页签「详情 / 队列」。
///
/// 关闭时宽度收到 0 而不是整块卸载，滑出/滑入与样例一致；内容常驻，
/// 切回详情不重新取数。
class DesktopDock extends ConsumerWidget {
  const DesktopDock({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final shell = ref.watch(desktopShellProvider);
    final controller = ref.read(desktopShellProvider.notifier);

    return DesktopGlassSurface(
      borderRadius: BorderRadius.zero,
      blur: 26,
      saturation: 1.4,
      child: AnimatedContainer(
        duration: DesktopMotion.of(context, DesktopMotion.dock),
        curve: DesktopMotion.ease,
        width: shell.dockOpen ? DesktopMetrics.dockWidth : 0,
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: skin.bg.withValues(alpha: 0.38),
          border: Border(
            left: BorderSide(
              color: skin.line,
              width: shell.dockOpen ? DesktopMetrics.hairline : 0,
            ),
          ),
        ),
        child: ClipRect(
          child: OverflowBox(
            // Dock 本身按样例从 0 到 348px 动画；内容保持完整规格，避免
            // 收放途中把页签行压窄后触发 RenderFlex 溢出。
            alignment: Alignment.centerLeft,
            minWidth: DesktopMetrics.dockWidth,
            maxWidth: DesktopMetrics.dockWidth,
            child: SizedBox(
              width: DesktopMetrics.dockWidth,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DesktopSeg<DesktopDockTab>(
                            options: DesktopDockTab.values,
                            value: shell.dockTab,
                            small: true,
                            labelOf:
                                (tab) =>
                                    tab == DesktopDockTab.details
                                        ? l10n.desktopDockDetails
                                        : l10n.desktopDockQueue,
                            onChanged: controller.setDockTab,
                          ),
                        ),
                        DesktopIconButton(
                          icon: DesktopIcons.close,
                          tooltip: l10n.desktopClosePanel,
                          onPressed: () => controller.setDock(false),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (shell.dockTab == DesktopDockTab.details)
                              _DetailsBody(detail: shell.detail)
                            else
                              const _QueueBody(),
                            const SizedBox(
                              height: DesktopMetrics.playerBarClearance,
                            ),
                          ],
                        ),
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

class _DetailsBody extends StatelessWidget {
  const _DetailsBody({required this.detail});

  final DesktopDetailData? detail;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final data = detail;
    if (data == null) {
      return DesktopEmpty(
        message: l10n.desktopDockEmpty,
        icon: DesktopIcons.info,
      );
    }
    final radius = BorderRadius.circular(14);
    Widget art;
    if (data.paperCover != null) {
      art = DesktopPaperCover(
        title: data.title,
        author: data.subtitle ?? '',
        tone: data.paperCover!.tone,
        ink: data.paperCover!.ink,
        compact: true,
      );
    } else if (data.imageUrl == null && data.kind == 'file') {
      art = ColoredBox(
        color: skin.raise2,
        child: Center(
          child: Icon(DesktopIcons.folder, size: 44, color: skin.accent),
        ),
      );
    } else {
      art = DesktopCover(
        url: data.imageUrl,
        kind:
            data.kind == 'track'
                ? DesktopCoverKind.music
                : DesktopCoverKind.network,
        fallbackIcon: switch (data.kind) {
          'track' => DesktopIcons.music,
          'book' => DesktopIcons.book,
          'file' => DesktopIcons.folder,
          _ => DesktopIcons.film,
        },
        iconSize: 40,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: data.squareArt ? 240 : 348),
            child: AspectRatio(
              aspectRatio: data.squareArt ? 1 : 16 / 10,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: radius,
                  boxShadow: data.kind == 'file' ? null : skin.shadow,
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    art,
                    if (data.badge != null)
                      Positioned(
                        left: 10,
                        top: 10,
                        child: DesktopChip(data.badge!),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          data.title,
          style:
              data.squareArt
                  ? DesktopType.displaySm(skin.text)
                  : DesktopType.display(skin.text),
        ),
        if (data.subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 14),
            child: Text(data.subtitle!, style: DesktopType.dense(skin.text2)),
          ),
        if (data.primary != null || data.secondary != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (data.primary != null)
                  DesktopButton(
                    label: data.primary!.label,
                    icon: data.primary!.icon,
                    variant: DesktopButtonVariant.primary,
                    onPressed: data.primary!.onPressed,
                  ),
                if (data.secondary != null)
                  DesktopButton(
                    label: data.secondary!.label,
                    icon: data.secondary!.icon,
                    variant: DesktopButtonVariant.soft,
                    onPressed: data.secondary!.onPressed,
                  ),
              ],
            ),
          ),
        if (data.progress != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: DesktopProgress(
              fraction: data.progress!,
              label: l10n.desktopProgressPercent(
                (data.progress! * 100).round(),
              ),
            ),
          ),
        if (data.about != null && data.about!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              data.about!,
              style: DesktopType.dense(skin.text2).copyWith(height: 1.6),
            ),
          ),
        if (data.chips.isNotEmpty) ...[
          DesktopEyebrow(data.chipsLabel ?? l10n.desktopCast),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final chip in data.chips) DesktopChip(chip)],
          ),
          const SizedBox(height: 14),
        ],
        if (data.facts.isNotEmpty) ...[
          DesktopEyebrow(l10n.desktopFileSection),
          DesktopKeyValues(entries: data.facts),
        ],
      ],
    );
  }
}

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
              onPressed: () {
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
              key: ValueKey('desktop-queue-${item.ref.playableKey}'),
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
                                tooltip: l10n.desktopDockClear,
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
