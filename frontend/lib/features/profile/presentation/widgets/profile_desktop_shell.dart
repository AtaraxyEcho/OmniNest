import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/theme/workstation_scope.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/core/widgets/animated_switcher_semantics.dart';
import 'package:omninest/core/widgets/user_avatar_menu.dart';
import 'package:omninest/core/widgets/workstation_portal_link.dart';
import 'package:omninest/features/notifications/notification_ui.dart';

enum ProfileSection {
  account('account'),
  appearance('appearance'),
  notifications('notifications'),
  security('security'),
  server('server'),
  about('about');

  const ProfileSection(this.value);

  final String value;

  static ProfileSection parse(String? value) {
    return ProfileSection.values.firstWhere(
      (section) => section.value == value,
      orElse: () => ProfileSection.account,
    );
  }
}

/// 个人中心桌面工位壳：56px 顶栏 + 248px 左侧导航 + 内容区。
///
/// 遵循建筑极简主义规范：0px 直角、1px 细线、零阴影；激活导航项
/// 纯靠底色与边框凸显，不附加任何伪线段。
class ProfileDesktopShell extends StatelessWidget {
  const ProfileDesktopShell({
    required this.selectedSection,
    required this.onSectionSelected,
    required this.displayName,
    required this.username,
    required this.role,
    required this.avatarUrl,
    required this.onBack,
    required this.onNotifications,
    required this.onSignOut,
    required this.child,
    super.key,
  });

  final ProfileSection selectedSection;
  final ValueChanged<ProfileSection> onSectionSelected;
  final String displayName;
  final String username;
  final String role;
  final String? avatarUrl;
  final VoidCallback onBack;
  final VoidCallback onNotifications;
  final VoidCallback onSignOut;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return WorkstationScope(
      child: Builder(
        builder: (context) {
          final scheme = Theme.of(context).colorScheme;
          return Scaffold(
            backgroundColor: scheme.surface,
            body: Column(
              children: [
                _ProfileTopBar(
                  onBack: onBack,
                  onNotifications: onNotifications,
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final navigationWidth =
                          constraints.maxWidth < 1180 ? 216.0 : 248.0;
                      final horizontalPadding =
                          constraints.maxWidth < 1180 ? 24.0 : 32.0;
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: navigationWidth,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border(
                                  right: BorderSide(
                                    color: scheme.outlineVariant,
                                  ),
                                ),
                              ),
                              child: Material(
                                color: scheme.surface,
                                child: _ProfileNavigation(
                                  selectedSection: selectedSection,
                                  onSectionSelected: onSectionSelected,
                                  displayName: displayName,
                                  username: username,
                                  role: role,
                                  avatarUrl: avatarUrl,
                                  onSignOut: onSignOut,
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: SingleChildScrollView(
                              padding: EdgeInsets.fromLTRB(
                                horizontalPadding,
                                28,
                                horizontalPadding,
                                48,
                              ),
                              child: Align(
                                alignment: Alignment.topCenter,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 1100,
                                  ),
                                  child: AnimatedSwitcher(
                                    duration:
                                        MediaQuery.disableAnimationsOf(context)
                                            ? Duration.zero
                                            : const Duration(milliseconds: 180),
                                    switchInCurve: Curves.easeOutQuart,
                                    switchOutCurve: Curves.easeInCubic,
                                    layoutBuilder: excludeExitingSemanticsStack,
                                    child: KeyedSubtree(
                                      key: ValueKey(selectedSection),
                                      child: child,
                                    ),
                                  ),
                                ),
                              ),
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
        },
      ),
    );
  }
}

/// 顶栏：PORTAL 返回 + mono 面包屑 + 通知铃铛 + 头像菜单。
class _ProfileTopBar extends StatelessWidget {
  const _ProfileTopBar({required this.onBack, required this.onNotifications});

  final VoidCallback onBack;
  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const WorkstationPortalLink(),
          const SizedBox(width: 12),
          SizedBox(
            height: 16,
            child: VerticalDivider(width: 1, color: scheme.outlineVariant),
          ),
          const SizedBox(width: 12),
          Text(
            'OMNINEST / ${l10n.profileBreadcrumbTitle}',
            style: TextStyle(
              fontFamily: AppTypography.monoFamily,
              fontFamilyFallback: AppTypography.monoFamilyFallback,
              fontSize: AppTypography.labelSmall,
              letterSpacing: 1.2,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          NotificationIcon(onPressed: onNotifications),
          const SizedBox(width: 8),
          const UserAvatarMenu(),
        ],
      ),
    );
  }
}

class _ProfileNavigation extends StatelessWidget {
  const _ProfileNavigation({
    required this.selectedSection,
    required this.onSectionSelected,
    required this.displayName,
    required this.username,
    required this.role,
    required this.avatarUrl,
    required this.onSignOut,
  });

  final ProfileSection selectedSection;
  final ValueChanged<ProfileSection> onSectionSelected;
  final String displayName;
  final String username;
  final String role;
  final String? avatarUrl;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        _NavigationUserCard(
          displayName: displayName,
          username: username,
          role: role,
          avatarUrl: avatarUrl,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _NavigationItem(
                icon: Icons.person_outline_rounded,
                label: l10n.profileSectionAccount,
                selected: selectedSection == ProfileSection.account,
                onTap: () => onSectionSelected(ProfileSection.account),
              ),
              const SizedBox(height: 2),
              _NavigationItem(
                icon: Icons.palette_outlined,
                label: l10n.profileSectionAppearance,
                selected: selectedSection == ProfileSection.appearance,
                onTap: () => onSectionSelected(ProfileSection.appearance),
              ),
              const SizedBox(height: 2),
              _NavigationItem(
                icon: Icons.notifications_outlined,
                label: l10n.profileSectionNotifications,
                selected: selectedSection == ProfileSection.notifications,
                onTap: () => onSectionSelected(ProfileSection.notifications),
              ),
              const SizedBox(height: 2),
              _NavigationItem(
                icon: Icons.security_outlined,
                label: l10n.profileSectionSecurity,
                selected: selectedSection == ProfileSection.security,
                onTap: () => onSectionSelected(ProfileSection.security),
              ),
              if (!isWebPlatform) ...[
                const SizedBox(height: 2),
                _NavigationItem(
                  icon: Icons.dns_outlined,
                  label: l10n.profileSectionServer,
                  selected: selectedSection == ProfileSection.server,
                  onTap: () => onSectionSelected(ProfileSection.server),
                ),
              ],
              const SizedBox(height: 2),
              _NavigationItem(
                icon: Icons.info_outline_rounded,
                label: l10n.profileSectionAbout,
                selected: selectedSection == ProfileSection.about,
                onTap: () => onSectionSelected(ProfileSection.about),
              ),
            ],
          ),
        ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.all(12),
          child: _SignOutButton(onSignOut: onSignOut),
        ),
      ],
    );
  }
}

/// 侧栏顶部用户卡：方形头像 + 名称 + @用户名 + 角色码徽章。
class _NavigationUserCard extends StatelessWidget {
  const _NavigationUserCard({
    required this.displayName,
    required this.username,
    required this.role,
    required this.avatarUrl,
  });

  final String displayName;
  final String username;
  final String role;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SquareAvatar(
                displayName: displayName,
                avatarUrl: avatarUrl,
                size: 44,
                fontSize: AppTypography.labelLarge,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppTypography.bodyMedium,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '@$username',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTypography.monoFamily,
                        fontFamilyFallback: AppTypography.monoFamilyFallback,
                        fontSize: AppTypography.labelSmall,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outlineVariant),
              color: scheme.surfaceContainer,
            ),
            child: Text(
              '[${role.toUpperCase()}]',
              style: TextStyle(
                fontFamily: AppTypography.monoFamily,
                fontFamilyFallback: AppTypography.monoFamilyFallback,
                fontSize: AppTypography.labelMicro,
                letterSpacing: 1.2,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 方形直角头像：有上传头像时铺图，否则回退等宽首字母。
class _SquareAvatar extends StatelessWidget {
  const _SquareAvatar({
    required this.displayName,
    required this.avatarUrl,
    required this.size,
    required this.fontSize,
  });

  final String displayName;
  final String? avatarUrl;
  final double size;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initial = displayName.isEmpty ? '?' : displayName.characters.first;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child:
          avatarUrl?.isNotEmpty == true
              ? Image.network(
                avatarUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _initial(initial, scheme),
              )
              : _initial(initial, scheme),
    );
  }

  Widget _initial(String initial, ColorScheme scheme) {
    return Center(
      child: Text(
        initial.toUpperCase(),
        style: TextStyle(
          fontFamily: AppTypography.monoFamily,
          fontFamilyFallback: AppTypography.monoFamilyFallback,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
    );
  }
}

/// 侧栏导航项：激活 = 容器底 + 细线边框，未激活纯靠变色，无伪线段。
class _NavigationItem extends StatefulWidget {
  const _NavigationItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavigationItem> createState() => _NavigationItemState();
}

class _NavigationItemState extends State<_NavigationItem> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = widget.selected;
    final foreground =
        selected || _hovering ? scheme.onSurface : scheme.onSurfaceVariant;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color:
                selected
                    ? scheme.surfaceContainerHigh
                    : _hovering
                    ? scheme.surfaceContainerLow
                    : Colors.transparent,
            border: Border.all(
              color: selected ? scheme.outlineVariant : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 16, color: foreground),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppTypography.labelMedium,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: foreground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 侧栏底部退出登录：整宽直角按钮，绯红描边语义。
class _SignOutButton extends StatefulWidget {
  const _SignOutButton({required this.onSignOut});

  final VoidCallback onSignOut;

  @override
  State<_SignOutButton> createState() => _SignOutButtonState();
}

class _SignOutButtonState extends State<_SignOutButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onSignOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color:
                _hovering
                    ? scheme.error.withValues(alpha: 0.08)
                    : Colors.transparent,
            border: Border.all(
              color:
                  _hovering
                      ? scheme.error.withValues(alpha: 0.55)
                      : scheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.logout_rounded,
                size: 14,
                color: _hovering ? scheme.error : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                l10n.coreSignOut,
                style: TextStyle(
                  fontSize: AppTypography.labelMedium,
                  fontWeight: FontWeight.w500,
                  color: _hovering ? scheme.error : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
