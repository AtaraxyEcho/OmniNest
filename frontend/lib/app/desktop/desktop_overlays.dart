import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/widgets/desktop_popovers.dart';
import 'package:omninest/app/desktop/desktop_shell_state.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_surfaces.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';

/// 居中模态的共同外壳（样例 `.scrim` + `.modal`）。
class DesktopModal extends StatelessWidget {
  const DesktopModal({
    required this.child,
    required this.onClose,
    this.width = 460,
    super.key,
  });

  final Widget child;
  final VoidCallback onClose;
  final double width;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Positioned.fill(
      // 样例 `Shell.tsx:408`：`role=dialog aria-modal=true`，读屏进入时先报
      // 这是对话框，并把背后的页面隔出去。
      child: Semantics(
        scopesRoute: true,
        explicitChildNodes: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onClose,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 1),
            duration: DesktopMotion.of(context, DesktopMotion.scrim),
            curve: DesktopMotion.ease,
            builder: (context, scrimT, content) {
              final scrimAlpha = skin.isDark ? 0.50 : 0.28;
              return ColoredBox(
                color: Colors.black.withValues(
                  alpha: scrimAlpha * scrimT.clamp(0.0, 1.0),
                ),
                child: content,
              );
            },
            child: Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: 1),
                duration: DesktopMotion.of(context, DesktopMotion.lift),
                curve: DesktopMotion.spring,
                builder:
                    (context, t, modalCard) => Opacity(
                      opacity: t.clamp(0.0, 1.0),
                      alwaysIncludeSemantics: true,
                      child: Transform.scale(
                        scale: 0.94 + 0.06 * t,
                        child: modalCard,
                      ),
                    ),
                child: GestureDetector(
                  onTap: () {},
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      width: width,
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.sizeOf(context).width - 40,
                        maxHeight: MediaQuery.sizeOf(context).height - 80,
                      ),
                      decoration: BoxDecoration(
                        color: skin.panelSolid,
                        borderRadius: BorderRadius.circular(
                          DesktopMetrics.radiusDialog,
                        ),
                        border: Border.all(color: skin.line2),
                        boxShadow: skin.shadow,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: SingleChildScrollView(child: child),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 模态标题行：眉标 + 衬线标题 + 关闭钮。
class DesktopModalHead extends StatelessWidget {
  const DesktopModalHead({
    required this.title,
    required this.onClose,
    this.eyebrow,
    super.key,
  });

  final String title;
  final String? eyebrow;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 16, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (eyebrow != null) DesktopEyebrow(eyebrow!),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(title, style: DesktopType.displaySm(skin.text)),
                ),
              ],
            ),
          ),
          DesktopIconButton(
            icon: DesktopIcons.close,
            tooltip: AppLocalizations.of(context).desktopPaletteClose,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

/// 键盘快捷键参考表（样例 `Shortcuts`）。
class DesktopShortcutsSheet extends ConsumerWidget {
  const DesktopShortcutsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final groups = <(String, List<(String, String)>)>[
      (
        l10n.desktopShortcutsNavigation,
        [
          (l10n.desktopShortcutPalette, 'Ctrl K'),
          (l10n.desktopShortcutGoTo, 'Alt 1–6'),
          (l10n.desktopShortcutSettings, 'Ctrl ,'),
          (l10n.desktopShortcutBackForward, 'Alt ← →'),
        ],
      ),
      (
        l10n.desktopShortcutsInterface,
        [
          (l10n.desktopShortcutSidebar, 'Ctrl B'),
          (l10n.desktopShortcutDetails, 'Ctrl .'),
          (l10n.desktopShortcutThisSheet, '?'),
          (l10n.desktopShortcutCloseOverlay, 'Esc'),
        ],
      ),
      (
        l10n.desktopShortcutsPlayback,
        [
          (l10n.desktopShortcutPlayPause, 'Space'),
          (l10n.desktopShortcutNextPrev, 'Ctrl → ←'),
          (l10n.desktopShortcutFullscreen, 'F'),
          (l10n.desktopShortcutSeek, '← →'),
        ],
      ),
      (
        l10n.desktopShortcutsFiles,
        [
          (l10n.desktopShortcutSelectAll, 'Ctrl A'),
          (l10n.desktopShortcutRename, 'F2'),
          (l10n.desktopShortcutDelete, 'Del'),
          (l10n.desktopShortcutOpenItem, 'Enter'),
        ],
      ),
    ];
    return DesktopModal(
      width: 760,
      onClose:
          () => ref.read(desktopShellProvider.notifier).setShortcuts(false),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DesktopModalHead(
            eyebrow: l10n.desktopReference,
            title: l10n.desktopKeyboardShortcuts,
            onClose:
                () =>
                    ref.read(desktopShellProvider.notifier).setShortcuts(false),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 26),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final twoColumns = constraints.maxWidth > 560;
                final children = <Widget>[
                  for (final group in groups)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DesktopEyebrow(group.$1),
                          const SizedBox(height: 6),
                          for (final row in group.$2)
                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: skin.line),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      row.$1,
                                      style: DesktopType.dense(skin.text),
                                    ),
                                  ),
                                  Text(
                                    row.$2,
                                    style: DesktopType.kbd(skin.text2),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                ];
                if (!twoColumns) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: children.take(2).toList(),
                      ),
                    ),
                    const SizedBox(width: 36),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: children.skip(2).toList(),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 右键菜单（样例 `ContextMenu`）：贴指针定位，自动避开视口边缘。
class DesktopContextMenu extends ConsumerStatefulWidget {
  const DesktopContextMenu({super.key});

  @override
  ConsumerState<DesktopContextMenu> createState() => _DesktopContextMenuState();
}

class _DesktopContextMenuState extends ConsumerState<DesktopContextMenu>
    with WidgetsBindingObserver {
  static const double _menuWidth = 240;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 样例 `Shell.tsx:299`：窗口失焦就收起菜单（`window.addEventListener("blur")`）。
  /// Flutter 桌面把失焦报成 `inactive`，之后才是 `paused/hidden`。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      final notifier = ref.read(desktopShellProvider.notifier);
      if (ref.read(desktopShellProvider).menu != null) {
        notifier.closeMenu();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final shell = ref.watch(desktopShellProvider);
    final menu = shell.menu;
    if (menu == null) {
      return const SizedBox.shrink();
    }
    final controller = ref.read(desktopShellProvider.notifier);
    return Stack(
      children: [
        Positioned.fill(
          // 样例同时监听 `scroll`（capture）收起菜单：菜单开着时任何滚动都
          // 说明指针已经不在菜单上，继续贴在旧位置就会错位。
          child: Listener(
            // translucent 才会把自身加进命中路径：默认 deferToChild 在空
            // GestureDetector 上返回 false，滚动信号根本到不了这里。
            behavior: HitTestBehavior.translucent,
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                controller.closeMenu();
              }
            },
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: controller.closeMenu,
              onSecondaryTap: controller.closeMenu,
            ),
          ),
        ),
        // 样例用 `getBoundingClientRect()` 实测菜单尺寸再钳进视口，分隔线
        // 与分组标题不按 34px 估算；这里交给布局代理拿真实 childSize。
        CustomSingleChildLayout(
          delegate: _ContextMenuLayout(anchor: menu.position),
          child: SizedBox(
            width: _menuWidth,
            child: DesktopPopover(
              width: _menuWidth,
              padding: const EdgeInsets.all(6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < menu.items.length; index++)
                    if (menu.items[index].separator)
                      Builder(
                        builder:
                            (context) => Container(
                              height: 1,
                              margin: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 5,
                              ),
                              color: DesktopSkin.of(context).line,
                            ),
                      )
                    else
                      DesktopMenuTile(
                        label: menu.items[index].label ?? '',
                        icon: menu.items[index].icon,
                        shortcut: menu.items[index].shortcut,
                        danger: menu.items[index].danger,
                        disabled: menu.items[index].disabled,
                        enterIndex: index,
                        onTap: () {
                          controller.closeMenu();
                          menu.items[index].onPressed?.call();
                        },
                      ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 右键菜单定位：先按指针位置放，再把实测尺寸钳进视口 8px 内边距。
class _ContextMenuLayout extends SingleChildLayoutDelegate {
  const _ContextMenuLayout({required this.anchor});

  final Offset anchor;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints.loose(constraints.biggest);
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    // 视口比菜单还窄时 clamp 的上下界会反过来，先用 max 兜住下界。
    final maxLeft = math.max(8.0, size.width - childSize.width - 8);
    final maxTop = math.max(8.0, size.height - childSize.height - 8);
    return Offset(anchor.dx.clamp(8.0, maxLeft), anchor.dy.clamp(8.0, maxTop));
  }

  @override
  bool shouldRelayout(_ContextMenuLayout oldDelegate) =>
      oldDelegate.anchor != anchor;
}
