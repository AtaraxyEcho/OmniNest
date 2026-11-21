import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_router_scope.dart';
import 'package:omninest/app/desktop/desktop_routes.dart';
import 'package:omninest/app/desktop/desktop_shell_state.dart';
import 'package:omninest/app/desktop/desktop_panels.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_glass.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/features/admin/application/admin_console_access_provider.dart';

/// 顶栏浮层的共同外壳（样例 `.pop`）：不透明玻璃 + 描边 + 投影，
/// 打开时按 `popin` 弹入（-6px、0.94 缩放、280ms spring）。
class DesktopPopover extends StatefulWidget {
  const DesktopPopover({
    required this.width,
    required this.child,
    this.maxHeight,
    this.padding = const EdgeInsets.all(14),
    super.key,
  });

  final double width;
  final Widget child;
  final double? maxHeight;
  final EdgeInsetsGeometry padding;

  @override
  State<DesktopPopover> createState() => _DesktopPopoverState();
}

class _DesktopPopoverState extends State<DesktopPopover>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: DesktopMotion.pop,
    value: 1,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller.value = 1;
    } else if (!_controller.isAnimating && _controller.value == 1) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = DesktopMotion.spring.transform(_controller.value);
        return Opacity(
          opacity: _controller.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, -6 * (1 - t)),
            child: Transform.scale(
              scale: 0.94 + 0.06 * t,
              alignment: Alignment.topRight,
              child: child,
            ),
          ),
        );
      },
      child: Material(
        color: Colors.transparent,
        child: DesktopOutsetShadow(
          borderRadius: BorderRadius.circular(DesktopMetrics.radiusPop),
          shadows: skin.shadow,
          child: DesktopGlassSurface(
            borderRadius: BorderRadius.circular(DesktopMetrics.radiusPop),
            blur: 30,
            saturation: 1.5,
            child: Container(
              width: widget.width,
              constraints: BoxConstraints(
                maxHeight:
                    widget.maxHeight ??
                    MediaQuery.sizeOf(context).height * 0.78,
              ),
              padding: widget.padding,
              decoration: BoxDecoration(
                color: skin.pop,
                borderRadius: BorderRadius.circular(DesktopMetrics.radiusPop),
                border: Border.all(color: skin.line2),
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// 浮层的定位容器：贴顶栏下沿、按锚点右对齐，点击外部关闭。
class DesktopPanelLayer extends ConsumerWidget {
  const DesktopPanelLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shell = ref.watch(desktopShellProvider);
    if (shell.panel == DesktopPanel.none) {
      return const SizedBox.shrink();
    }
    final controller = ref.read(desktopShellProvider.notifier);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final rightInset = switch (shell.panel) {
      DesktopPanel.account => 150.0,
      DesktopPanel.notifications => 150.0,
      DesktopPanel.tasks => 190.0,
      DesktopPanel.none => 20.0,
    };
    final width = switch (shell.panel) {
      DesktopPanel.account => 270.0,
      DesktopPanel.notifications => 400.0,
      DesktopPanel.tasks => 420.0,
      DesktopPanel.none => 0.0,
    };
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => controller.setPanel(DesktopPanel.none),
          ),
        ),
        Positioned(
          top: DesktopMetrics.titleBarHeight + 2,
          right: rightInset.clamp(16.0, screenWidth - width - 16),
          child: switch (shell.panel) {
            DesktopPanel.account => DesktopPopover(
              width: width,
              padding: const EdgeInsets.all(6),
              child: const _AccountMenu(),
            ),
            DesktopPanel.notifications => DesktopPopover(
              width: width,
              child: const NotificationsPanel(),
            ),
            DesktopPanel.tasks => DesktopPopover(
              width: width,
              child: const TasksPanel(),
            ),
            DesktopPanel.none => const SizedBox.shrink(),
          },
        ),
      ],
    );
  }
}

class _AccountMenu extends ConsumerWidget {
  const _AccountMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final shell = ref.read(desktopShellProvider.notifier);
    final user = ref.watch(authSessionProvider).asData?.value.user;
    final canAdmin = ref.watch(canAccessAdminConsoleProvider);
    final name =
        (user?.displayName?.trim().isNotEmpty ?? false)
            ? user!.displayName!.trim()
            : (user?.username ?? '');
    final roles = {...?user?.roles, if (user != null) user.role};
    final roleLabel =
        roles.contains('SUPER_ADMIN')
            ? l10n.desktopRoleOwner
            : roles.contains('ADMIN')
            ? l10n.desktopRoleAdmin
            : l10n.desktopRoleMember;

    void run(VoidCallback action) {
      shell.setPanel(DesktopPanel.none);
      action();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      skin.accent,
                      Color.lerp(skin.accent, skin.warm, 0.55)!,
                    ],
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  name.isEmpty ? '·' : name.characters.first.toUpperCase(),
                  style: DesktopType.bodyStrong(skin.accentInk),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DesktopType.bodyStrong(skin.text),
                    ),
                    Text(roleLabel, style: DesktopType.caption(skin.text3)),
                  ],
                ),
              ),
            ],
          ),
        ),
        _MenuDivider(),
        DesktopMenuTile(
          enterIndex: 0,
          icon: DesktopIcons.settings,
          label: l10n.desktopNavSettings,
          shortcut: 'Ctrl ,',
          onTap: () => run(() => desktopGo(context, DesktopRoutes.settings)),
        ),
        DesktopMenuTile(
          enterIndex: 1,
          icon: DesktopIcons.wallpaper,
          label: l10n.desktopBackdropLibrary,
          onTap:
              () =>
                  run(() => desktopGo(context, DesktopRoutes.settingsBackdrop)),
        ),
        DesktopMenuTile(
          enterIndex: 3,
          icon: DesktopIcons.bell,
          label: l10n.desktopNotifications,
          onTap: () => shell.setPanel(DesktopPanel.notifications),
        ),
        DesktopMenuTile(
          enterIndex: 4,
          icon: DesktopIcons.tasks,
          label: l10n.desktopBackgroundTasks,
          onTap: () => shell.setPanel(DesktopPanel.tasks),
        ),
        DesktopMenuTile(
          enterIndex: 5,
          icon: DesktopIcons.command,
          label: l10n.desktopKeyboardShortcuts,
          shortcut: '?',
          onTap: () => run(() => shell.setShortcuts(true)),
        ),
        DesktopMenuTile(
          enterIndex: 6,
          icon: DesktopIcons.shield,
          label: l10n.desktopSecuritySessions,
          onTap:
              () =>
                  run(() => desktopGo(context, DesktopRoutes.settingsSecurity)),
        ),
        if (canAdmin)
          DesktopMenuTile(
            enterIndex: 7,
            icon: DesktopIcons.server,
            label: l10n.desktopAdminConsole,
            onTap: () => run(() => desktopGo(context, DesktopRoutes.admin)),
          ),
        _MenuDivider(),
        DesktopMenuTile(
          enterIndex: 8,
          icon: DesktopIcons.signOut,
          label: l10n.desktopSignOut,
          onTap:
              () => run(
                () => ref.read(authSessionProvider.notifier).clearSession(),
              ),
        ),
      ],
    );
  }
}

class _MenuDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      color: skin.line,
    );
  }
}

/// 菜单项（样例 `.mi`），详情坞与右键菜单共用。
class DesktopMenuTile extends StatelessWidget {
  const DesktopMenuTile({
    required this.label,
    this.icon,
    this.shortcut,
    this.onTap,
    this.danger = false,
    this.disabled = false,
    this.enterIndex,
    super.key,
  });

  final String label;
  final IconData? icon;
  final String? shortcut;
  final VoidCallback? onTap;
  final bool danger;
  final bool disabled;

  /// 菜单内序号：按样例 `animation-delay: calc(var(--i) * 14ms)` 逐项错开。
  final int? enterIndex;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final foreground =
        disabled
            ? skin.text3
            : danger
            ? skin.bad
            : skin.text;
    final tile = Opacity(
      opacity: disabled ? 0.4 : 1,
      child: DesktopHover(
        enabled: !disabled && onTap != null,
        builder:
            (context, hovered) => GestureDetector(
              onTap: disabled ? null : onTap,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: hovered ? skin.raise2 : Colors.transparent,
                  borderRadius: BorderRadius.circular(
                    DesktopMetrics.radiusSmall,
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      child:
                          icon == null
                              ? null
                              : Icon(icon, size: 16, color: foreground),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DesktopType.dense(foreground),
                      ),
                    ),
                    if (shortcut != null)
                      Text(shortcut!, style: DesktopType.nano(skin.text3)),
                  ],
                ),
              ),
            ),
      ),
    );
    final index = enterIndex;
    if (index == null) {
      return tile;
    }
    return DesktopRise(
      delay: DesktopMotion.menuStagger(context, index),
      duration: DesktopMotion.soft,
      offset: 0,
      offsetX: -4,
      child: tile,
    );
  }
}
