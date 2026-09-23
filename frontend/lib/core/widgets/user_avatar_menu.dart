import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/appearance/application/appearance_controller.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/locale/application/locale_controller.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/mobile_layout_tokens.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/widgets/anchored_popover.dart';
import 'package:omninest/core/widgets/confirm_action_dialog.dart';
import 'package:omninest/core/widgets/hover_scale.dart';

/// 右上角头像下拉菜单组件。
///
/// 弹层结构参照 Reader 重构原型：控件下方右对齐的直角分区卡（hairline
/// 分隔）、用户信息、主题与语言行内小描边按钮（显示切换目标，点击即切
/// 换不关闭）、操作区整行按钮；入口为双线描边圆形头像，打开态边框转前
/// 景色。
class UserAvatarMenu extends ConsumerStatefulWidget {
  const UserAvatarMenu({
    super.key,
    this.size = 32,
    this.directToProfile = false,
  });

  /// 头像尺寸（宽高），默认 32，与移动端全局顶部栏一致。
  final double size;

  /// 是否直接进入个人中心，移动端全局顶部栏使用该模式。
  final bool directToProfile;

  @override
  ConsumerState<UserAvatarMenu> createState() => _UserAvatarMenuState();
}

class _UserAvatarMenuState extends ConsumerState<UserAvatarMenu> {
  final AnchoredPopover _popover = AnchoredPopover();

  @override
  void dispose() {
    _popover.close();
    super.dispose();
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  void _closeAndRun(VoidCallback action) {
    _popover.close(onChanged: _refresh);
    action();
  }

  /// 面板动作统一走宿主 context 导航，避免引用已卸载的面板节点。
  void _go(String location) {
    if (mounted) {
      context.go(location);
    }
  }

  /// Admin 入口用 push 保留 Portal shell 状态（返回时 pop 即可）。
  void _push(String location) {
    if (mounted) {
      context.push(location);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final authState = ref.watch(authSessionProvider);
    final user = authState.asData?.value.user;
    final displayName = user?.displayName ?? user?.username ?? '?';
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
    final avatarUrl = user?.avatarUrl;

    if (widget.directToProfile) {
      final avatar = _AvatarWidget(
        avatarUrl: avatarUrl,
        initial: initial,
        size: widget.size,
        emphasized: false,
      );
      return SizedBox.square(
        dimension: 48,
        child: Tooltip(
          message: l10n.coreProfile,
          child: InkResponse(
            onTap: () => context.push('/profile'),
            radius: 24,
            customBorder: const CircleBorder(),
            child: Center(child: avatar),
          ),
        ),
      );
    }

    final open = _popover.isOpen;
    final avatar = _AvatarWidget(
      avatarUrl: avatarUrl,
      initial: initial,
      size: widget.size,
      emphasized: open,
    );
    return HoverScale(
      child: Tooltip(
        message: l10n.coreProfile,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          hoverColor: Colors.transparent,
          onTap: () {
            if (open) {
              _popover.close(onChanged: _refresh);
            } else {
              _popover.open(context, _buildPanel, onChanged: _refresh);
            }
          },
          child: avatar,
        ),
      ),
    );
  }

  Widget _buildPanel(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final l10n = AppLocalizations.of(context);
        final colors = Theme.of(context).colorScheme;
        final themeMode = ref.watch(appearanceControllerProvider);
        final languageCode = ref.watch(localeControllerProvider);
        final user = ref.watch(
          authSessionProvider.select((state) => state.asData?.value.user),
        );
        final displayName = user?.displayName ?? user?.username ?? '?';
        final initial =
            displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
        final role = user?.role ?? 'MEMBER';
        return Material(
          color: colors.surfaceContainerLow,
          shadowColor: colors.shadow.withValues(alpha: 0.55),
          elevation: 6,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
            side: BorderSide(color: colors.outlineVariant),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 232, maxWidth: 280),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _UserHeader(
                  displayName: displayName,
                  username: user?.username ?? '',
                  role: role,
                  avatarUrl: user?.avatarUrl,
                  initial: initial,
                ),
                _MenuDivider(),
                _PreferenceRow(
                  label: l10n.settingsAppearance,
                  trailing: _ThemeCycleButton(themeMode: themeMode),
                ),
                _MenuDivider(),
                _PreferenceRow(
                  label: l10n.settingsLanguage,
                  trailing: _LanguageCycleButton(languageCode: languageCode),
                ),
                _MenuDivider(),
                _MenuActionRow(
                  icon: Icons.person_outline_rounded,
                  label: l10n.coreProfile,
                  onTap: () => _closeAndRun(() => _go('/profile')),
                ),
                _MenuActionRow(
                  icon: Icons.cloud_outlined,
                  label: l10n.coreStorage,
                  onTap: () => _closeAndRun(() => _go('/files')),
                ),
                if (role == 'SUPER_ADMIN' || role == 'ADMIN')
                  _MenuActionRow(
                    icon: Icons.admin_panel_settings_outlined,
                    label: l10n.coreAdmin,
                    onTap: () => _closeAndRun(() => _push('/admin')),
                  ),
                _MenuActionRow(
                  icon: Icons.logout_rounded,
                  label: l10n.coreSignOut,
                  destructive: true,
                  onTap:
                      () => _closeAndRun(() => _confirmSignOut(context, l10n)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 登出属破坏性操作：二次确认后才清除会话。面板已先行关闭，
  /// 对话框挂在宿主 context 上。
  Future<void> _confirmSignOut(
    BuildContext context,
    AppLocalizations l10n,
  ) async {
    if (!mounted) {
      return;
    }
    final confirmed = await confirmDestructiveAction(
      context,
      title: l10n.coreSignOutConfirmTitle,
      message: l10n.coreSignOutConfirmMessage,
      confirmLabel: l10n.coreSignOut,
    );
    if (!confirmed || !mounted) {
      return;
    }
    await ref.read(authSessionProvider.notifier).clearSession();
  }
}

/// 偏好行：左侧灰字标签 + 右侧行内小描边切换按钮。
class _PreferenceRow extends StatelessWidget {
  const _PreferenceRow({required this.label, required this.trailing});

  final String label;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: AppTypography.bodySmall,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

/// 主题循环小描边按钮：仅在浅色与深色之间切换（不进入跟随系统）。
///
/// 若当前为跟随系统，点击后落入浅色并从此只在浅/深之间循环。
class _ThemeCycleButton extends ConsumerWidget {
  const _ThemeCycleButton({required this.themeMode});

  final ThemeMode themeMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // 跟随系统不参与循环；当前为浅色或系统时，下一步为深色；当前为深色时回到浅色。
    final next = themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    final (icon, label) =
        next == ThemeMode.dark
            ? (Icons.dark_mode_outlined, l10n.settingsThemeDark)
            : (Icons.light_mode_outlined, l10n.settingsThemeLight);
    return _SmallOutlineButton(
      icon: icon,
      label: label,
      mono: false,
      onTap:
          () => unawaited(
            ref.read(appearanceControllerProvider.notifier).setThemeMode(next),
          ),
    );
  }
}

/// 语言循环小描边按钮：显示切换目标（中文 ↔ English）。
class _LanguageCycleButton extends ConsumerWidget {
  const _LanguageCycleButton({required this.languageCode});

  final String languageCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final next = languageCode == 'zh' ? 'en' : 'zh';
    final label =
        next == 'en'
            ? l10n.settingsLanguageEnglish
            : l10n.settingsLanguageChinese;
    return _SmallOutlineButton(
      icon: null,
      label: label,
      mono: true,
      onTap:
          () => unawaited(
            ref.read(localeControllerProvider.notifier).setLanguage(next),
          ),
    );
  }
}

/// h-6 行内小描边按钮，点击切换偏好且不关闭面板。
class _SmallOutlineButton extends StatelessWidget {
  const _SmallOutlineButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.mono,
  });

  final IconData? icon;
  final String label;
  final VoidCallback onTap;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textStyle = TextStyle(
      fontSize: AppTypography.labelSmall,
      color: colors.onSurfaceVariant,
      fontFamily: mono ? AppTypography.monoFamily : null,
      fontFamilyFallback: mono ? AppTypography.monoFamilyFallback : null,
    );
    // 描边与文字保持 24 高的可见胶囊，命中区按壳层标准抬到 48：
    // Flutter 命中区等于自身布局盒，因此把描边从 Material 移到内层盒。
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: MobileLayoutTokens.minimumTarget,
          child: Center(
            child: Container(
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 12, color: colors.onSurfaceVariant),
                    const SizedBox(width: 4),
                  ],
                  Text(label, style: textStyle),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 操作行：整行点击，hover 加底色。
class _MenuActionRow extends StatelessWidget {
  const _MenuActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = destructive ? colors.error : colors.onSurface;
    return InkWell(
      borderRadius: BorderRadius.zero,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: AppTypography.bodySmall,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// hairline 分隔线。
class _MenuDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      color: Theme.of(
        context,
      ).colorScheme.outlineVariant.withValues(alpha: 0.55),
    );
  }
}

/// 头像显示组件，优先网络图片，降级为首字母渐变。
/// [emphasized] 为打开态：双线描边并转前景色。
class _AvatarWidget extends StatelessWidget {
  const _AvatarWidget({
    required this.avatarUrl,
    required this.initial,
    this.size = 36,
    this.emphasized = false,
  });

  final String? avatarUrl;
  final String initial;
  final double size;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor =
        emphasized
            ? theme.colorScheme.onSurface
            : theme.colorScheme.outlineVariant.withValues(alpha: 0.32);
    final borderWidth = size >= 28 ? 2.0 : 1.0;
    final content =
        avatarUrl != null && avatarUrl!.isNotEmpty
            ? Image.network(
              avatarUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _AvatarFallback(initial: initial),
            )
            : _AvatarFallback(initial: initial);
    // 显式 ClipOval 保证任意平台上头像均为正圆，双线描边以覆盖层绘制。
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipOval(
              child: ColoredBox(
                color: theme.colorScheme.surfaceContainerHighest,
                child: content,
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: borderColor, width: borderWidth),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 首字母降级头像：纯色底（禁渐变规范）。
class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({required this.initial});

  final String initial;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.primaryContainer,
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: theme.colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w700,
          fontSize: AppTypography.titleMedium,
        ),
      ),
    );
  }
}

/// 菜单头部：头像 + 用户名 + 角色标签。
class _UserHeader extends StatelessWidget {
  const _UserHeader({
    required this.displayName,
    required this.username,
    required this.role,
    required this.avatarUrl,
    required this.initial,
  });

  final String displayName;
  final String username;
  final String role;
  final String? avatarUrl;
  final String initial;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final roleLabel = switch (role) {
      'SUPER_ADMIN' => l10n.coreRoleSuperAdmin,
      'ADMIN' => l10n.coreRoleAdmin,
      _ => l10n.coreRoleMember,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.surfaceContainerHighest,
            ),
            child:
                avatarUrl != null && avatarUrl!.isNotEmpty
                    ? Image.network(
                      avatarUrl!,
                      fit: BoxFit.cover,
                      errorBuilder:
                          (_, _, _) => _AvatarFallback(initial: initial),
                    )
                    : _AvatarFallback(initial: initial),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        username,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _RoleBadge(role: role, label: roleLabel),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 角色标签。
class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role, required this.label});

  final String role;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (role) {
      'SUPER_ADMIN' => theme.colorScheme.error,
      'ADMIN' => theme.colorScheme.tertiary,
      _ => theme.colorScheme.outline,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: AppTypography.labelSmall,
        ),
      ),
    );
  }
}
