import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_player_bar.dart'
    show formatDesktopClock;
import 'package:omninest/app/desktop/desktop_router_scope.dart';
import 'package:omninest/app/desktop/desktop_routes.dart';
import 'package:omninest/app/desktop/desktop_shell_state.dart';
import 'package:omninest/app/desktop/desktop_toast.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_cover.dart';
import 'package:omninest/app/desktop/widgets/desktop_dialogs.dart';
import 'package:omninest/app/desktop/widgets/desktop_glass.dart';
import 'package:omninest/app/desktop/widgets/desktop_surfaces.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/core/utils/file_size_formatter.dart';
import 'package:omninest/core/widgets/animated_switcher_semantics.dart';
import 'package:omninest/features/files/file_dashboard.dart';
import 'package:omninest/features/music/music_portal.dart';
import 'package:omninest/features/photos/photo_dashboard.dart';
import 'package:omninest/platform/file_pick.dart';

part 'desktop_dock_overview.dart';
part 'desktop_dock_queue.dart';

/// 右侧详情坞（样例 `.dock`）：348px，两个页签「详情 / 队列」。
///
/// 关闭时宽度滑收至 0，动画期间隔离语义、指针与焦点，动画结束后卸载内部
/// `BackdropFilter(26)` 与 348px 子树以消除 GPU 浪费与 Windows `AXTree` 报错。
class DesktopDock extends ConsumerStatefulWidget {
  const DesktopDock({super.key});

  @override
  ConsumerState<DesktopDock> createState() => _DesktopDockState();
}

class _DesktopDockState extends ConsumerState<DesktopDock> {
  late bool _mountedContent;

  @override
  void initState() {
    super.initState();
    _mountedContent = ref.read(desktopShellProvider.select((s) => s.dockOpen));
  }

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final dockOpen = ref.watch(desktopShellProvider.select((s) => s.dockOpen));
    final dockTab = ref.watch(desktopShellProvider.select((s) => s.dockTab));
    final detail = ref.watch(desktopShellProvider.select((s) => s.detail));
    final controller = ref.read(desktopShellProvider.notifier);

    if (dockOpen && !_mountedContent) {
      _mountedContent = true;
    }

    return ExcludeSemantics(
      excluding: !dockOpen,
      child: IgnorePointer(
        ignoring: !dockOpen,
        child: FocusScope(
          canRequestFocus: dockOpen,
          child: AnimatedContainer(
            duration: DesktopMotion.of(context, DesktopMotion.dock),
            curve: DesktopMotion.ease,
            width: dockOpen ? DesktopMetrics.dockWidth : 0,
            onEnd: () {
              if (!mounted) {
                return;
              }
              final isOpen = ref.read(
                desktopShellProvider.select((s) => s.dockOpen),
              );
              if (!isOpen && _mountedContent) {
                setState(() => _mountedContent = false);
              }
            },
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(
              color: _mountedContent ? skin.bg.withValues(alpha: 0.38) : null,
              border: Border(
                left: BorderSide(
                  color: skin.line,
                  width: dockOpen ? DesktopMetrics.hairline : 0,
                ),
              ),
            ),
            child:
                _mountedContent
                    ? DesktopGlassSurface(
                      borderRadius: BorderRadius.zero,
                      blur: 26,
                      saturation: 1.4,
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
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      DesktopSeg<DesktopDockTab>(
                                        options: DesktopDockTab.values,
                                        value: dockTab,
                                        small: true,
                                        labelOf:
                                            (tab) =>
                                                tab == DesktopDockTab.details
                                                    ? l10n.desktopDockDetails
                                                    : l10n.desktopDockQueue,
                                        onChanged: controller.setDockTab,
                                      ),
                                      DesktopIconButton(
                                        icon: DesktopIcons.close,
                                        tooltip: l10n.desktopClosePanel,
                                        onPressed:
                                            () => controller.setDock(false),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  Expanded(
                                    child: SingleChildScrollView(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          if (dockTab == DesktopDockTab.details)
                                            _DetailsBody(detail: detail)
                                          else
                                            const _QueueBody(),
                                          const SizedBox(
                                            height:
                                                DesktopMetrics
                                                    .playerBarClearance,
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
                    )
                    : const Offstage(offstage: true, child: SizedBox.shrink()),
          ),
        ),
      ),
    );
  }
}

class _DetailsBody extends ConsumerWidget {
  const _DetailsBody({required this.detail});

  final DesktopDetailData? detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final data = detail;

    final Widget content;
    if (data == null) {
      content = const _ContextualOverviewBody(
        key: ValueKey('dock-detail-overview'),
      );
    } else {
      final radius = BorderRadius.circular(14);
      final previewUrl = data.effectivePreviewUrl;
      final defaultFallbackIcon =
          data.fallbackIcon ??
          switch (data.kind) {
            'track' => DesktopIcons.music,
            'book' => DesktopIcons.book,
            'photo' => DesktopIcons.image,
            'file' => data.isFolder ? DesktopIcons.folder : DesktopIcons.file,
            _ => DesktopIcons.film,
          };

      Widget art;
      if (data.customPreview != null) {
        art = data.customPreview!;
      } else if (data.paperCover != null) {
        art = DesktopPaperCover(
          title: data.title,
          author: data.subtitle ?? '',
          tone: data.paperCover!.tone,
          ink: data.paperCover!.ink,
          compact: true,
        );
      } else if (previewUrl != null &&
          data.thumbnailHeaders != null &&
          data.thumbnailHeaders!.isNotEmpty) {
        art = Image.network(
          previewUrl,
          headers: data.thumbnailHeaders,
          fit: BoxFit.cover,
          errorBuilder:
              (_, _, _) => ColoredBox(
                color: skin.raise2,
                child: Center(
                  child: Icon(
                    defaultFallbackIcon,
                    size: 40,
                    color: skin.accent,
                  ),
                ),
              ),
        );
      } else if (previewUrl == null && data.kind == 'file') {
        art = ColoredBox(
          color: skin.raise2,
          child: Center(
            child: Icon(defaultFallbackIcon, size: 44, color: skin.accent),
          ),
        );
      } else {
        art = DesktopCover(
          url: previewUrl,
          kind:
              data.kind == 'track'
                  ? DesktopCoverKind.music
                  : DesktopCoverKind.network,
          fallbackIcon: defaultFallbackIcon,
          iconSize: 40,
        );
      }

      final hasActions =
          data.primary != null ||
          data.secondary != null ||
          data.extraActions.isNotEmpty;

      content = KeyedSubtree(
        key: ValueKey(data.effectiveId),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.center,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: data.squareArt ? 240 : 348,
                ),
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
                child: Text(
                  data.subtitle!,
                  style: DesktopType.dense(skin.text2),
                ),
              ),
            if (hasActions)
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
                        variant:
                            data.primary!.danger
                                ? DesktopButtonVariant.danger
                                : DesktopButtonVariant.primary,
                        onPressed: () => data.primary!.onPressed(context, ref),
                      ),
                    if (data.secondary != null)
                      DesktopButton(
                        label: data.secondary!.label,
                        icon: data.secondary!.icon,
                        variant:
                            data.secondary!.danger
                                ? DesktopButtonVariant.danger
                                : DesktopButtonVariant.soft,
                        onPressed:
                            () => data.secondary!.onPressed(context, ref),
                      ),
                    for (final action in data.extraActions)
                      DesktopButton(
                        label: action.label,
                        icon: action.icon,
                        variant:
                            action.danger
                                ? DesktopButtonVariant.danger
                                : DesktopButtonVariant.ghost,
                        onPressed: () => action.onPressed(context, ref),
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
              DesktopEyebrow(data.factsLabel ?? l10n.desktopFileSection),
              DesktopKeyValues(entries: data.facts),
            ],
            if (data.extraSection != null) ...[
              const SizedBox(height: 16),
              data.extraSection!,
            ],
          ],
        ),
      );
    }

    return AnimatedSwitcher(
      duration: DesktopMotion.of(context, DesktopMotion.fast),
      switchInCurve: DesktopMotion.ease,
      switchOutCurve: DesktopMotion.ease,
      layoutBuilder: excludeExitingSemanticsStack,
      transitionBuilder: semanticsSafeFadeTransition,
      child: content,
    );
  }
}

/// 方案 C 零空态上下文概览：当未选中具体条目时，根据当前路由实时渲染
/// 对应模块的目录/图库/正在播放/快捷导航概览，彻底消灭空屏。
