import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/appearance/application/font_scale_controller.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/mobile_layout_tokens.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/core/widgets/brand_logo.dart';
import 'package:omninest/features/backdrop/backdrop_ui.dart';
import 'package:omninest/features/profile/presentation/widgets/change_password_dialog.dart';
import 'package:omninest/features/profile/presentation/widgets/profile_session_management_panel.dart';

/// 个人中心在移动端使用的单列信息架构。
class ProfileMobileContent extends ConsumerWidget {
  const ProfileMobileContent({
    required this.displayName,
    required this.username,
    required this.email,
    required this.role,
    required this.unreadCount,
    required this.onEditAvatar,
    required this.onEditWeatherCity,
    required this.themeMode,
    required this.languageCode,
    required this.fontScalePreset,
    required this.onThemeChanged,
    required this.onLanguageChanged,
    required this.onFontScaleChanged,
    this.avatarUrl,
    this.weatherCity,
    super.key,
  });

  final String displayName;
  final String username;
  final String email;
  final String role;
  final String? avatarUrl;
  final int unreadCount;
  final String? weatherCity;
  final VoidCallback onEditAvatar;
  final VoidCallback onEditWeatherCity;
  final ThemeMode themeMode;
  final String languageCode;
  final FontScalePreset fontScalePreset;
  final ValueChanged<ThemeMode> onThemeChanged;
  final ValueChanged<String> onLanguageChanged;
  final ValueChanged<FontScalePreset> onFontScaleChanged;

  bool get _isAdmin => role == 'SUPER_ADMIN' || role == 'ADMIN';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return MobilePageSurface(
      exposeBackdrop: true,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          MobileLayoutTokens.pagePadding(context).left,
          18,
          MobileLayoutTokens.pagePadding(context).right,
          32 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          _ProfileIdentityHeader(
            displayName: displayName,
            username: username,
            role: _roleLabel(l10n),
            avatarUrl: avatarUrl,
            onEditAvatar: onEditAvatar,
          ),
          const SizedBox(height: MobileLayoutTokens.sectionGap),
          MobileSettingsGroup(
            title: l10n.profileAccountInfo,
            children: [
              MobileSettingsTile(
                icon: Icons.alternate_email_rounded,
                title: l10n.profileUsername,
                subtitle: username,
              ),
              MobileSettingsTile(
                icon: Icons.mail_outline_rounded,
                title: l10n.profileEmail,
                subtitle: email,
              ),
              MobileSettingsTile(
                icon: Icons.notifications_none_rounded,
                title: l10n.notificationTitle,
                subtitle: l10n.notificationTitleWithCount(unreadCount),
                onTap: () => context.push('/notifications'),
              ),
              MobileSettingsTile(
                icon: Icons.tune_rounded,
                title: l10n.profileNotificationSettings,
                subtitle: l10n.profileNotificationMasterSwitchHint,
                onTap: () => context.push('/profile/notifications'),
              ),
            ],
          ),
          const SizedBox(height: MobileLayoutTokens.sectionGap),
          MobileSettingsGroup(
            title: l10n.settingsAppearance,
            children: [
              MobileSettingsTile(
                icon: Icons.wallpaper_rounded,
                title: l10n.portalLocalBackdropTitle,
                subtitle: l10n.portalLocalBackdropSubtitle,
                iconColor: context.mobileColors.warmAccent,
                onTap: () => _showBackdropSettings(context),
              ),
              MobileSettingsTile(
                icon: Icons.location_city_rounded,
                title: l10n.profileWeatherCity,
                subtitle:
                    weatherCity?.isNotEmpty == true
                        ? weatherCity
                        : l10n.profileWeatherCityNotSet,
                onTap: onEditWeatherCity,
              ),
              MobileSettingsTile(
                icon: Icons.contrast_rounded,
                title: l10n.settingsAppearance,
                subtitle: _themeLabel(l10n),
                onTap: () => _showThemePicker(context),
              ),
              MobileSettingsTile(
                icon: Icons.format_size_rounded,
                title: l10n.fontScaleTitle,
                subtitle: _fontScaleLabel(l10n),
                onTap: () => _showFontScalePicker(context),
              ),
              MobileSettingsTile(
                icon: Icons.language_rounded,
                title: l10n.settingsLanguage,
                subtitle:
                    languageCode == 'zh'
                        ? l10n.settingsLanguageChinese
                        : l10n.settingsLanguageEnglish,
                onTap: () => _showLanguagePicker(context),
              ),
            ],
          ),
          const SizedBox(height: MobileLayoutTokens.sectionGap),
          MobileSettingsGroup(
            title: l10n.settingsSecurity,
            children: [
              MobileSettingsTile(
                icon: Icons.lock_outline_rounded,
                title: l10n.profileChangePassword,
                subtitle: l10n.profileChangePasswordSubtitle,
                onTap: () => _showChangePassword(context),
              ),
              MobileSettingsTile(
                icon: Icons.devices_rounded,
                title: l10n.profileSessionManagement,
                subtitle: l10n.profileSessionManagementSubtitle,
                onTap: () => _showSessions(context),
              ),
            ],
          ),
          if (_isAdmin) ...[
            const SizedBox(height: MobileLayoutTokens.sectionGap),
            MobileSettingsGroup(
              title: l10n.coreAdmin,
              children: [
                MobileSettingsTile(
                  icon: Icons.admin_panel_settings_outlined,
                  title: l10n.coreAdmin,
                  subtitle: l10n.portalAdminSubtitle,
                  iconColor: context.mobileColors.warmAccent,
                  onTap: () => context.push('/admin'),
                ),
              ],
            ),
          ],
          const SizedBox(height: MobileLayoutTokens.sectionGap),
          MobileSettingsGroup(
            title: l10n.settingsAbout,
            children: [
              MobileSettingsTile(
                icon: Icons.info_outline_rounded,
                title: l10n.settingsAbout,
                subtitle: l10n.settingsAboutHint,
                onTap: () => _showAbout(context),
              ),
              MobileSettingsTile(
                icon: Icons.logout_rounded,
                title: l10n.coreSignOut,
                destructive: true,
                onTap:
                    () => ref.read(authSessionProvider.notifier).clearSession(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _roleLabel(AppLocalizations l10n) {
    return switch (role) {
      'SUPER_ADMIN' => l10n.profileRoleSuperAdmin,
      'ADMIN' => l10n.profileRoleAdmin,
      _ => l10n.profileRoleMember,
    };
  }

  String _themeLabel(AppLocalizations l10n) {
    return switch (themeMode) {
      ThemeMode.system => l10n.settingsThemeSystem,
      ThemeMode.light => l10n.settingsThemeLight,
      ThemeMode.dark => l10n.settingsThemeDark,
    };
  }

  Future<void> _showThemePicker(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder:
          (sheetContext) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ChoiceTile(
                  icon: Icons.brightness_auto_rounded,
                  label: l10n.settingsThemeSystem,
                  selected: themeMode == ThemeMode.system,
                  onTap: () {
                    onThemeChanged(ThemeMode.system);
                    Navigator.pop(sheetContext);
                  },
                ),
                _ChoiceTile(
                  icon: Icons.light_mode_rounded,
                  label: l10n.settingsThemeLight,
                  selected: themeMode == ThemeMode.light,
                  onTap: () {
                    onThemeChanged(ThemeMode.light);
                    Navigator.pop(sheetContext);
                  },
                ),
                _ChoiceTile(
                  icon: Icons.dark_mode_rounded,
                  label: l10n.settingsThemeDark,
                  selected: themeMode == ThemeMode.dark,
                  onTap: () {
                    onThemeChanged(ThemeMode.dark);
                    Navigator.pop(sheetContext);
                  },
                ),
              ],
            ),
          ),
    );
  }

  Future<void> _showFontScalePicker(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder:
          (sheetContext) => SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final preset in FontScalePreset.values)
                    _ChoiceTile(
                      icon:
                          preset == FontScalePreset.followSystem
                              ? Icons.brightness_auto_rounded
                              : Icons.format_size_rounded,
                      label: _presetLabel(preset, l10n),
                      selected: fontScalePreset == preset,
                      onTap: () {
                        onFontScaleChanged(preset);
                        Navigator.pop(sheetContext);
                      },
                    ),
                ],
              ),
            ),
          ),
    );
  }

  String _fontScaleLabel(AppLocalizations l10n) {
    return _presetLabel(fontScalePreset, l10n);
  }

  String _presetLabel(FontScalePreset preset, AppLocalizations l10n) {
    return switch (preset) {
      FontScalePreset.followSystem => l10n.fontScaleFollowSystem,
      FontScalePreset.compact => l10n.fontScaleCompact,
      FontScalePreset.standard => l10n.fontScaleStandard,
      FontScalePreset.comfortable => l10n.fontScaleComfortable,
      FontScalePreset.large => l10n.fontScaleLarge,
    };
  }

  Future<void> _showLanguagePicker(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder:
          (sheetContext) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ChoiceTile(
                  icon: Icons.translate_rounded,
                  label: l10n.settingsLanguageChinese,
                  selected: languageCode == 'zh',
                  onTap: () {
                    onLanguageChanged('zh');
                    Navigator.pop(sheetContext);
                  },
                ),
                _ChoiceTile(
                  icon: Icons.language_rounded,
                  label: l10n.settingsLanguageEnglish,
                  selected: languageCode == 'en',
                  onTap: () {
                    onLanguageChanged('en');
                    Navigator.pop(sheetContext);
                  },
                ),
              ],
            ),
          ),
    );
  }

  Future<void> _showBackdropSettings(BuildContext context) {
    return showAppBackdropSettings(context);
  }

  Future<void> _showChangePassword(BuildContext context) {
    return showDialog(
      context: context,
      builder: (_) => const ChangePasswordDialog(),
    );
  }

  Future<void> _showSessions(BuildContext context) {
    final height = math.min(MediaQuery.sizeOf(context).height * 0.78, 620.0);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.mobileColors.surface,
      showDragHandle: true,
      builder:
          (context) => SafeArea(
            child: SizedBox(
              height: height,
              child: const SingleChildScrollView(
                child: ProfileSessionManagementPanel(framed: false),
              ),
            ),
          ),
    );
  }

  void _showAbout(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    showAboutDialog(
      context: context,
      applicationName: 'OmniNest',
      applicationIcon: const BrandLogo(size: 48, radius: 10),
      applicationVersion: l10n.settingsAboutHint,
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
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
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: selected ? const Icon(Icons.check_rounded) : null,
      onTap: onTap,
    );
  }
}

class _ProfileIdentityHeader extends StatelessWidget {
  const _ProfileIdentityHeader({
    required this.displayName,
    required this.username,
    required this.role,
    required this.onEditAvatar,
    this.avatarUrl,
  });

  final String displayName;
  final String username;
  final String role;
  final String? avatarUrl;
  final VoidCallback onEditAvatar;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final initial = displayName.isEmpty ? '?' : displayName.characters.first;
    return Row(
      children: [
        Semantics(
          button: true,
          label: l10n.profileEditAvatar,
          child: InkResponse(
            onTap: onEditAvatar,
            radius: 42,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 76,
                  height: 76,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: context.mobileColors.surfaceRaised,
                  ),
                  child:
                      avatarUrl?.isNotEmpty == true
                          ? Image.network(
                            avatarUrl!,
                            fit: BoxFit.cover,
                            errorBuilder:
                                (_, _, _) => _AvatarFallback(initial: initial),
                          )
                          : _AvatarFallback(initial: initial),
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: context.mobileColors.musicAccent,
                    ),
                    child: Icon(
                      Icons.edit_rounded,
                      size: 15,
                      color: context.mobileColors.pageMask,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.mobileColors.textPrimary,
                  fontSize: AppTypography.headlineSmall,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '@$username · $role',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.mobileColors.textSecondary,
                  fontSize: AppTypography.bodyMedium,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({required this.initial});

  final String initial;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.mobileColors.surfaceSelected,
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            color: context.mobileColors.textPrimary,
            fontSize: AppTypography.headlineMedium,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
