import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/global_theme_colors.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/core/widgets/workbench_top_bar.dart';

enum ProfileSection {
  account('account'),
  appearance('appearance'),
  notifications('notifications'),
  security('security'),
  server('server'),
  backup('backup'),
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
    final l10n = AppLocalizations.of(context);
    final colors = context.globalColors;
    return Scaffold(
      backgroundColor: colors.surfaceContainerLowest,
      body: Column(
        children: [
          WorkbenchTopBar(
            surfaceColor: colors.surface,
            borderColor: colors.outlineVariant,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  IconButton(
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back_rounded),
                    tooltip: l10n.profileBackTooltip,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l10n.profileTitle,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: onNotifications,
                    icon: const Icon(Icons.notifications_none_rounded),
                    tooltip: l10n.notificationTitle,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final navigationWidth =
                    constraints.maxWidth < 1180 ? 220.0 : 248.0;
                final horizontalPadding =
                    constraints.maxWidth < 1180 ? 24.0 : 36.0;
                return Row(
                  children: [
                    SizedBox(
                      width: navigationWidth,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border(
                            right: BorderSide(color: colors.outlineVariant),
                          ),
                        ),
                        child: Material(
                          color: colors.surfaceContainerLow,
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
                            constraints: const BoxConstraints(maxWidth: 1280),
                            child: AnimatedSwitcher(
                              duration:
                                  MediaQuery.disableAnimationsOf(context)
                                      ? Duration.zero
                                      : const Duration(milliseconds: 180),
                              switchInCurve: Curves.easeOutQuart,
                              switchOutCurve: Curves.easeInCubic,
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
    final colors = context.globalColors;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 14),
          child: Row(
            children: [
              _NavigationAvatar(displayName: displayName, avatarUrl: avatarUrl),
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
                        color: colors.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '@$username',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: AppTypography.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: colors.outlineVariant),
        const SizedBox(height: 10),
        _NavigationItem(
          icon: Icons.person_outline_rounded,
          label: l10n.profileSectionAccount,
          selected: selectedSection == ProfileSection.account,
          onTap: () => onSectionSelected(ProfileSection.account),
        ),
        _NavigationItem(
          icon: Icons.palette_outlined,
          label: l10n.profileSectionAppearance,
          selected: selectedSection == ProfileSection.appearance,
          onTap: () => onSectionSelected(ProfileSection.appearance),
        ),
        _NavigationItem(
          icon: Icons.notifications_outlined,
          label: l10n.profileSectionNotifications,
          selected: selectedSection == ProfileSection.notifications,
          onTap: () => onSectionSelected(ProfileSection.notifications),
        ),
        _NavigationItem(
          icon: Icons.security_outlined,
          label: l10n.profileSectionSecurity,
          selected: selectedSection == ProfileSection.security,
          onTap: () => onSectionSelected(ProfileSection.security),
        ),
        if (!isWebPlatform)
          _NavigationItem(
            icon: Icons.dns_outlined,
            label: l10n.profileSectionServer,
            selected: selectedSection == ProfileSection.server,
            onTap: () => onSectionSelected(ProfileSection.server),
          ),
        _NavigationItem(
          icon: Icons.cloud_sync_outlined,
          label: l10n.profileSectionBackup,
          selected: selectedSection == ProfileSection.backup,
          onTap: () => onSectionSelected(ProfileSection.backup),
        ),
        _NavigationItem(
          icon: Icons.info_outline_rounded,
          label: l10n.profileSectionAbout,
          selected: selectedSection == ProfileSection.about,
          onTap: () => onSectionSelected(ProfileSection.about),
        ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  _roleLabel(l10n),
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: AppTypography.bodySmall,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: Icon(Icons.logout_rounded, color: colors.error),
                title: Text(
                  l10n.coreSignOut,
                  style: TextStyle(color: colors.error),
                ),
                minTileHeight: 44,
                onTap: onSignOut,
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _roleLabel(AppLocalizations l10n) {
    return switch (role) {
      'SUPER_ADMIN' => l10n.profileRoleSuperAdmin,
      'ADMIN' => l10n.profileRoleAdmin,
      _ => l10n.profileRoleMember,
    };
  }
}

class _NavigationAvatar extends StatelessWidget {
  const _NavigationAvatar({required this.displayName, required this.avatarUrl});

  final String displayName;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final colors = context.globalColors;
    final initial = displayName.isEmpty ? '?' : displayName.characters.first;
    return Container(
      width: 42,
      height: 42,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.primaryContainer,
      ),
      child:
          avatarUrl?.isNotEmpty == true
              ? Image.network(
                avatarUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _initial(initial, colors),
              )
              : _initial(initial, colors),
    );
  }

  Widget _initial(String initial, GlobalThemeColors colors) {
    return Center(
      child: Text(
        initial,
        style: TextStyle(
          color: colors.onPrimaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _NavigationItem extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final colors = context.globalColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: ListTile(
        selected: selected,
        leading: Icon(icon, size: 20),
        title: Text(label),
        minTileHeight: 44,
        onTap: onTap,
        selectedTileColor: colors.selectedOverlay,
      ),
    );
  }
}
