import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omninest/app/appearance/application/appearance_controller.dart';
import 'package:omninest/app/desktop/desktop_brand.dart';
import 'package:omninest/app/desktop/desktop_backdrop_layer.dart';
import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_router_scope.dart';
import 'package:omninest/app/desktop/desktop_shell_state.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_glass.dart';
import 'package:omninest/app/desktop/widgets/desktop_window_controls.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/core/window/window_chrome_controller.dart';
import 'package:omninest/features/notifications/application/notification_controller.dart';
import 'package:omninest/features/files/application/media_import_queue_controller.dart';
import 'package:omninest/features/tasks/application/task_controller.dart';

/// 样例 `.avatar` 的第二停色：`color-mix(in oklab, accent 45%, #6b4a8a)` 的基色。
const Color _avatarSecond = Color(0xFF6B4A8A);

/// 桌面标题栏（样例 `.titlebar`）：46px 高，三栏网格
/// 「品牌与导航 / 搜索胶囊 / 状态与账户」。
class DesktopTitleBar extends ConsumerWidget {
  const DesktopTitleBar({required this.path, super.key});

  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final shell = ref.watch(desktopShellProvider);
    final history = ref.watch(desktopHistoryProvider);
    final shellController = ref.read(desktopShellProvider.notifier);
    final historyController = ref.read(desktopHistoryProvider.notifier);
    final unread = ref.watch(unreadCountProvider);
    final tasks = ref.watch(activeTaskSummaryProvider).asData?.value;
    final mediaImports = ref.watch(mediaImportQueueProvider);
    final running =
        (tasks?.activeCount ?? 0) +
        mediaImports.where((task) => task.isActive).length;
    final themeMode = ref.watch(appearanceControllerProvider);
    final isDark =
        themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);
    final backdropActive = desktopBackdropVisibleForRoute(ref, path);

    // 无边框窗口没有系统标题栏可拖：整条标题栏自己当拖拽区，
    // 双击按 Windows 惯例切换最大化。子按钮仍拿到自己的点击（手势竞技场里
    // 按钮的 tap 优先，拖动只在空白处成立）。
    final bar = Container(
      height: DesktopMetrics.titleBarHeight,
      decoration: BoxDecoration(
        color: skin.bg.withValues(alpha: backdropActive ? 0.38 : 0.62),
        border: Border(bottom: BorderSide(color: skin.line)),
      ),
      padding: const EdgeInsets.only(left: 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxWidth <= DesktopMetrics.titleBarCompactBreakpoint;
          final left = _TitleBarLeft(
            l10n: l10n,
            shell: shell,
            history: history,
            onToggleSidebar: shellController.toggleSidebar,
            onBack: () {
              final target = historyController.back();
              if (target != null && context.mounted) {
                desktopGo(context, target);
              }
            },
            onForward: () {
              final target = historyController.forward();
              if (target != null && context.mounted) {
                desktopGo(context, target);
              }
            },
          );
          final search = _SearchPill(
            key: const ValueKey<String>('desktop-titlebar-search'),
            label: l10n.desktopSearchPill,
            onTap: shellController.toggleCommandPalette,
          );
          final right = _TitleBarRight(
            l10n: l10n,
            shell: shell,
            isDark: isDark,
            running: running,
            unread: unread,
            onToggleTheme:
                () => ref
                    .read(appearanceControllerProvider.notifier)
                    .setThemeMode(isDark ? ThemeMode.light : ThemeMode.dark),
            onToggleTasks:
                () => shellController.togglePanel(DesktopPanel.tasks),
            onToggleNotifications:
                () => shellController.togglePanel(DesktopPanel.notifications),
            onToggleDock: shellController.toggleDock,
            onToggleAccount:
                () => shellController.togglePanel(DesktopPanel.account),
          );

          // `desktop.css:174` 的宽屏网格是 1fr / 280–520px / 1fr。
          // 左右内容宽度不同也必须保持搜索中心在窗口中心；窄窗则按
          // `desktop.css:500` 收成 auto / 1fr / auto，避免按钮挤压搜索。
          return compact
              ? Row(
                children: [
                  left,
                  const SizedBox(width: 10),
                  Expanded(child: search),
                  const SizedBox(width: 10),
                  right,
                ],
              )
              : Row(
                children: [
                  Expanded(
                    child: Align(alignment: Alignment.centerLeft, child: left),
                  ),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minWidth: 280,
                          maxWidth: 520,
                        ),
                        child: search,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: right,
                    ),
                  ),
                ],
              );
        },
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart:
          isDesktopPlatform
              ? (_) =>
                  ref
                      .read(windowChromeControllerProvider.notifier)
                      .startDragging()
              : null,
      onDoubleTap:
          isDesktopPlatform
              ? () =>
                  ref
                      .read(windowChromeControllerProvider.notifier)
                      .toggleMaximize()
              : null,
      child:
          backdropActive
              ? DesktopGlassSurface(
                borderRadius: BorderRadius.zero,
                blur: 26,
                saturation: 1.4,
                child: bar,
              )
              : bar,
    );
  }
}

class _TitleBarLeft extends StatelessWidget {
  const _TitleBarLeft({
    required this.l10n,
    required this.shell,
    required this.history,
    required this.onToggleSidebar,
    required this.onBack,
    required this.onForward,
  });

  final AppLocalizations l10n;
  final DesktopShellState shell;
  final DesktopHistory history;
  final VoidCallback onToggleSidebar;
  final VoidCallback onBack;
  final VoidCallback onForward;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.only(right: 8),
          child: DesktopBrandLockup(),
        ),
        DesktopIconButton(
          icon: DesktopIcons.sidebar,
          tooltip: '${l10n.desktopToggleSidebar} (Ctrl+B)',
          onPressed: onToggleSidebar,
          active: !shell.sidebarExpanded,
        ),
        DesktopIconButton(
          icon: DesktopIcons.left,
          tooltip: '${l10n.desktopBack} (Alt+←)',
          onPressed: history.canGoBack ? onBack : null,
        ),
        DesktopIconButton(
          icon: DesktopIcons.chevron,
          tooltip: '${l10n.desktopForward} (Alt+→)',
          onPressed: history.canGoForward ? onForward : null,
        ),
      ],
    );
  }
}

class _TitleBarRight extends StatelessWidget {
  const _TitleBarRight({
    required this.l10n,
    required this.shell,
    required this.isDark,
    required this.running,
    required this.unread,
    required this.onToggleTheme,
    required this.onToggleTasks,
    required this.onToggleNotifications,
    required this.onToggleDock,
    required this.onToggleAccount,
  });

  final AppLocalizations l10n;
  final DesktopShellState shell;
  final bool isDark;
  final int running;
  final int unread;
  final VoidCallback onToggleTheme;
  final VoidCallback onToggleTasks;
  final VoidCallback onToggleNotifications;
  final VoidCallback onToggleDock;
  final VoidCallback onToggleAccount;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DesktopIconButton(
          icon: DesktopIcons.moon,
          glyph: _ThemeGlyph(isDark: isDark),
          tooltip: l10n.desktopToggleTheme,
          onPressed: onToggleTheme,
        ),
        DesktopIconButton(
          icon: DesktopIcons.tasks,
          tooltip: l10n.desktopBackgroundTasks,
          active: shell.panel == DesktopPanel.tasks,
          badge: running,
          badgeColor: running > 0 ? skin.warm : null,
          onPressed: onToggleTasks,
        ),
        DesktopIconButton(
          icon: DesktopIcons.bell,
          tooltip: l10n.desktopNotifications,
          active: shell.panel == DesktopPanel.notifications,
          badge: unread,
          onPressed: onToggleNotifications,
        ),
        DesktopIconButton(
          icon: DesktopIcons.panel,
          tooltip: '${l10n.desktopDetailsPanel} (Ctrl+.)',
          active: shell.dockOpen,
          onPressed: onToggleDock,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: _AvatarButton(
            key: const ValueKey<String>('desktop-account-button'),
            active: shell.panel == DesktopPanel.account,
            onTap: onToggleAccount,
          ),
        ),
        if (isDesktopPlatform) ...[
          const SizedBox(width: 4),
          const DesktopWindowControls(),
        ],
      ],
    );
  }
}

/// 主题图标交接（样例 `.theme-ico`）：日月同栈，一个转 90° 缩到 0.3 退场，
/// 另一个从反方向转回来，600ms 弹簧。
class _ThemeGlyph extends StatelessWidget {
  const _ThemeGlyph({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final duration = DesktopMotion.of(context, DesktopMotion.soft);
    Widget layer(IconData icon, bool visible, double hiddenTurns) {
      return AnimatedOpacity(
        duration: duration,
        opacity: visible ? 1 : 0,
        child: AnimatedRotation(
          duration: duration,
          curve: DesktopMotion.spring,
          turns: visible ? 0 : hiddenTurns,
          child: AnimatedScale(
            duration: duration,
            curve: DesktopMotion.spring,
            scale: visible ? 1 : 0.3,
            child: Icon(
              icon,
              size: DesktopMetrics.iconSmall + 1,
              color: skin.text2,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: DesktopMetrics.iconSmall + 1,
      height: DesktopMetrics.iconSmall + 1,
      child: Stack(
        fit: StackFit.expand,
        children: [
          layer(DesktopIcons.moon, isDark, 0.25),
          layer(DesktopIcons.sun, !isDark, -0.25),
        ],
      ),
    );
  }
}

class _SearchPill extends StatelessWidget {
  const _SearchPill({required this.label, required this.onTap, super.key});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return DesktopHover(
      builder:
          (context, hovered) => GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: DesktopOutsetShadow(
              borderRadius: BorderRadius.circular(DesktopMetrics.radiusButton),
              shadows:
                  hovered
                      ? [
                        BoxShadow(
                          color: skin.accent.withValues(alpha: 0.14),
                          blurRadius: 0,
                          spreadRadius: 3,
                        ),
                      ]
                      : const <BoxShadow>[],
              child: AnimatedContainer(
                duration: MotionToken.reduced(context, MotionToken.fast),
                curve: MotionToken.curve,
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: hovered ? skin.raise2 : skin.raise,
                  borderRadius: BorderRadius.circular(
                    DesktopMetrics.radiusButton,
                  ),
                  border: Border.all(color: hovered ? skin.line2 : skin.line),
                ),
                child: Row(
                  children: [
                    Icon(
                      DesktopIcons.search,
                      size: DesktopMetrics.iconSmall,
                      color: hovered ? skin.text2 : skin.text3,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DesktopType.dense(
                          hovered ? skin.text2 : skin.text3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _Kbd(label: 'Ctrl'),
                    const SizedBox(width: 3),
                    _Kbd(label: 'K'),
                  ],
                ),
              ),
            ),
          ),
    );
  }
}

class _Kbd extends StatelessWidget {
  const _Kbd({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: skin.raise,
        borderRadius: BorderRadius.circular(5),
        border: Border(
          top: BorderSide(color: skin.line2),
          left: BorderSide(color: skin.line2),
          right: BorderSide(color: skin.line2),
          bottom: BorderSide(color: skin.line2, width: 2),
        ),
      ),
      child: Text(label, style: DesktopType.kbd(skin.text2)),
    );
  }
}

class _AvatarButton extends ConsumerWidget {
  const _AvatarButton({required this.active, required this.onTap, super.key});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final user = ref.watch(authSessionProvider).asData?.value.user;
    final name =
        (user?.displayName?.trim().isNotEmpty ?? false)
            ? user!.displayName!.trim()
            : (user?.username ?? '');
    final initial = name.isEmpty ? '·' : name.characters.first.toUpperCase();
    final avatar = user?.avatarUrl;

    return Semantics(
      button: true,
      label: l10n.desktopAccount,
      child: DesktopHover(
        builder:
            (context, hovered) => GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: AnimatedScale(
                duration: MotionToken.reduced(context, MotionToken.fast),
                curve: MotionToken.curve,
                scale: hovered ? 1.08 : 1,
                child: Container(
                  width: 30,
                  height: 30,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        skin.accent,
                        // 样例 `.avatar`：`color-mix(in oklab, accent 45%, #6b4a8a)`。
                        // 该停色只用于头像渐变，保持与参考样例一致的局部表现。
                        Color.lerp(_avatarSecond, skin.accent, 0.45)!,
                      ],
                    ),
                    border:
                        active
                            ? Border.all(color: skin.accent, width: 2)
                            : null,
                  ),
                  alignment: Alignment.center,
                  child:
                      avatar == null || avatar.isEmpty
                          ? Text(
                            initial,
                            style: DesktopType.denseStrong(skin.accentInk),
                          )
                          : Image.network(
                            avatar,
                            fit: BoxFit.cover,
                            width: 30,
                            height: 30,
                            errorBuilder:
                                (context, error, stack) => Text(
                                  initial,
                                  style: DesktopType.denseStrong(
                                    skin.accentInk,
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
