import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/appearance/application/font_scale_controller.dart';
import 'package:omninest/app/environment_providers.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/mobile_layout_tokens.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/feedback/omni_feedback.dart';
import 'package:omninest/core/utils/download_url_opener.dart';
import 'package:omninest/core/version/app_version_api.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/core/widgets/brand_logo.dart';
import 'package:omninest/features/backdrop/backdrop_ui.dart';
import 'package:omninest/features/profile/presentation/widgets/change_password_dialog.dart';
import 'package:omninest/features/profile/presentation/widgets/profile_server_panel.dart';
import 'package:omninest/features/profile/presentation/widgets/profile_two_factor_card.dart';
import 'package:omninest/features/profile/presentation/widgets/profile_session_management_panel.dart';
import 'package:omninest/core/widgets/mobile_sheet_semantics.dart';

/// 个人中心在移动端使用的单列信息架构。
/// 深链分区锚定键：与桌面 rail 的 section id 对应（notifications 无
/// 独立分组，由 /profile/notifications 专页承担）。
const Set<String> _profileAnchorSections = <String>{
  'account',
  'appearance',
  'security',
};

class ProfileMobileContent extends ConsumerStatefulWidget {
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
    this.initialSection,
    super.key,
  });

  /// 深链目标分区（?section=）：移动端长页滚动锚定到对应设置组。
  final String? initialSection;

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

  @override
  ConsumerState<ProfileMobileContent> createState() =>
      _ProfileMobileContentState();
}

class _ProfileMobileContentState extends ConsumerState<ProfileMobileContent> {
  final Map<String, GlobalKey> _sectionKeys = {
    for (final section in _profileAnchorSections)
      section: GlobalKey(debugLabel: 'profile-section-$section'),
  };

  bool _checkingUpdate = false;

  /// 最近一次检查结果，作为「检查更新」行的副标题留在列表里。
  String? _updateResultMessage;

  @override
  void initState() {
    super.initState();
    final section = widget.initialSection;
    if (section == null || !_profileAnchorSections.contains(section)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final target = _sectionKeys[section]?.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(
          target,
          alignment: 0.06,
          duration: const Duration(milliseconds: 280),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
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
            displayName: widget.displayName,
            username: widget.username,
            role: _roleLabel(l10n),
            avatarUrl: widget.avatarUrl,
            onEditAvatar: widget.onEditAvatar,
          ),
          const SizedBox(height: MobileLayoutTokens.sectionGap),
          MobileSettingsGroup(
            key: _sectionKeys['account'],
            title: l10n.profileAccountInfo,
            children: [
              MobileSettingsTile(
                icon: Icons.alternate_email_rounded,
                title: l10n.profileUsername,
                subtitle: widget.username,
              ),
              MobileSettingsTile(
                icon: Icons.mail_outline_rounded,
                title: l10n.profileEmail,
                subtitle: widget.email,
              ),
              MobileSettingsTile(
                icon: Icons.notifications_none_rounded,
                title: l10n.notificationTitle,
                subtitle: l10n.notificationTitleWithCount(widget.unreadCount),
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
            key: _sectionKeys['appearance'],
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
                    widget.weatherCity?.isNotEmpty == true
                        ? widget.weatherCity
                        : l10n.profileWeatherCityNotSet,
                onTap: widget.onEditWeatherCity,
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
                    widget.languageCode == 'zh'
                        ? l10n.settingsLanguageChinese
                        : l10n.settingsLanguageEnglish,
                onTap: () => _showLanguagePicker(context),
              ),
            ],
          ),
          const SizedBox(height: MobileLayoutTokens.sectionGap),
          MobileSettingsGroup(
            key: _sectionKeys['security'],
            title: l10n.settingsSecurity,
            children: [
              MobileSettingsTile(
                icon: Icons.lock_outline_rounded,
                title: l10n.profileChangePassword,
                subtitle: l10n.profileChangePasswordSubtitle,
                onTap: () => _showChangePassword(context),
              ),
              MobileSettingsTile(
                icon: Icons.verified_user_outlined,
                title: l10n.profileTwoFactorTitle,
                subtitle: l10n.profileTwoFactorSubtitle,
                onTap: () => _showTwoFactor(context),
              ),
              MobileSettingsTile(
                icon: Icons.devices_rounded,
                title: l10n.profileSessionManagement,
                subtitle: l10n.profileSessionManagementSubtitle,
                onTap: () => _showSessions(context),
              ),
            ],
          ),
          if (!isWebPlatform) ...[
            const SizedBox(height: MobileLayoutTokens.sectionGap),
            MobileSettingsGroup(
              title: l10n.profileSectionServer,
              children: [
                Consumer(
                  builder: (context, tileRef, _) {
                    final environment = tileRef.watch(appEnvironmentProvider);
                    return MobileSettingsTile(
                      icon: Icons.dns_rounded,
                      title: l10n.serverPanelCurrent,
                      subtitle: environment?.apiBaseUrl ?? '-',
                      onTap: () => _showServer(context),
                    );
                  },
                ),
              ],
            ),
          ],
          // Admin 仅桌面端开放；移动端个人中心不提供管理台入口。
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
                icon: Icons.system_update_outlined,
                title: l10n.settingsCheckUpdate,
                subtitle: _updateResultMessage ?? l10n.settingsAboutHint,
                onTap: _checkingUpdate ? null : () => unawaited(_checkUpdate()),
              ),
              MobileSettingsTile(
                icon: Icons.logout_rounded,
                title: l10n.coreSignOut,
                destructive: true,
                onTap: () => unawaited(_confirmSignOut(context, ref, l10n)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 退出登录属破坏性操作：与桌面端与移动其它入口一致，先二次确认再清会话。
  Future<void> _confirmSignOut(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final confirmed = await showMobileConfirmSheet(
      context,
      title: l10n.coreSignOutConfirmTitle,
      message: l10n.coreSignOutConfirmMessage,
      confirmLabel: l10n.coreSignOut,
      destructive: true,
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    await ref.read(authSessionProvider.notifier).clearSession();
  }

  String _roleLabel(AppLocalizations l10n) {
    return switch (widget.role) {
      'SUPER_ADMIN' => l10n.profileRoleSuperAdmin,
      'ADMIN' => l10n.profileRoleAdmin,
      _ => l10n.profileRoleMember,
    };
  }

  String _themeLabel(AppLocalizations l10n) {
    return switch (widget.themeMode) {
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
          (sheetContext) => MobileSheetSemantics(
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ChoiceTile(
                    icon: Icons.brightness_auto_rounded,
                    label: l10n.settingsThemeSystem,
                    selected: widget.themeMode == ThemeMode.system,
                    onTap: () {
                      widget.onThemeChanged(ThemeMode.system);
                      Navigator.pop(sheetContext);
                    },
                  ),
                  _ChoiceTile(
                    icon: Icons.light_mode_rounded,
                    label: l10n.settingsThemeLight,
                    selected: widget.themeMode == ThemeMode.light,
                    onTap: () {
                      widget.onThemeChanged(ThemeMode.light);
                      Navigator.pop(sheetContext);
                    },
                  ),
                  _ChoiceTile(
                    icon: Icons.dark_mode_rounded,
                    label: l10n.settingsThemeDark,
                    selected: widget.themeMode == ThemeMode.dark,
                    onTap: () {
                      widget.onThemeChanged(ThemeMode.dark);
                      Navigator.pop(sheetContext);
                    },
                  ),
                ],
              ),
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
          (sheetContext) => MobileSheetSemantics(
            child: SafeArea(
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
                        selected: widget.fontScalePreset == preset,
                        onTap: () {
                          widget.onFontScaleChanged(preset);
                          Navigator.pop(sheetContext);
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
    );
  }

  String _fontScaleLabel(AppLocalizations l10n) {
    return _presetLabel(widget.fontScalePreset, l10n);
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
          (sheetContext) => MobileSheetSemantics(
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ChoiceTile(
                    icon: Icons.translate_rounded,
                    label: l10n.settingsLanguageChinese,
                    selected: widget.languageCode == 'zh',
                    onTap: () {
                      widget.onLanguageChanged('zh');
                      Navigator.pop(sheetContext);
                    },
                  ),
                  _ChoiceTile(
                    icon: Icons.language_rounded,
                    label: l10n.settingsLanguageEnglish,
                    selected: widget.languageCode == 'en',
                    onTap: () {
                      widget.onLanguageChanged('en');
                      Navigator.pop(sheetContext);
                    },
                  ),
                ],
              ),
            ),
          ),
    );
  }

  Future<void> _showBackdropSettings(BuildContext context) {
    return showAppBackdropSettings(context);
  }

  Future<void> _showChangePassword(BuildContext context) {
    return ChangePasswordDialog.show(context);
  }

  Future<void> _showSessions(BuildContext context) {
    final height = math.min(MediaQuery.sizeOf(context).height * 0.78, 620.0);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.mobileColors.surface,
      showDragHandle: true,
      builder:
          (context) => MobileSheetSemantics(
            child: SafeArea(
              child: SizedBox(
                height: height,
                child: const SingleChildScrollView(
                  child: ProfileSessionManagementPanel(framed: false),
                ),
              ),
            ),
          ),
    );
  }

  /// 两步验证在桌面分区里可达；移动端按同一弹层方式承载，避免只有桌面能开。
  Future<void> _showTwoFactor(BuildContext context) {
    final height = math.min(MediaQuery.sizeOf(context).height * 0.78, 620.0);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.mobileColors.surface,
      showDragHandle: true,
      builder:
          (context) => MobileSheetSemantics(
            child: SafeArea(
              child: SizedBox(
                height: height,
                child: const SingleChildScrollView(
                  child: ProfileTwoFactorCard(framed: false),
                ),
              ),
            ),
          ),
    );
  }

  Future<void> _showServer(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.mobileColors.surface,
      showDragHandle: true,
      builder:
          (context) => MobileSheetSemantics(
            child: const SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: ProfileServerPanel(),
              ),
            ),
          ),
    );
  }

  /// 检查更新：与桌面端 about 面板同一套判据，移动端用弹层与反馈条承载。
  Future<void> _checkUpdate() async {
    if (_checkingUpdate) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    setState(() => _checkingUpdate = true);
    AppVersionInfo? info;
    String? failure;
    try {
      info = await ref.read(appVersionApiProvider).version();
    } on Object catch (error) {
      failure = describeUserFacingError(error).message;
    }
    if (!mounted) {
      return;
    }
    final latestVersion = info?.latestVersion;
    final downloadUrl = info?.downloadUrl;
    final message =
        failure != null
            ? l10n.settingsCheckUpdateFailed(failure)
            : latestVersion == null
            ? l10n.settingsAlreadyLatest
            : l10n.settingsNewVersionFound(latestVersion);
    setState(() {
      _checkingUpdate = false;
      _updateResultMessage = message;
    });
    if (failure == null && latestVersion != null && downloadUrl != null) {
      final open = await showMobileConfirmSheet(
        context,
        title: l10n.settingsCheckUpdate,
        message: message,
        confirmLabel: l10n.settingsOpenDownloadPage,
      );
      if (open && mounted) {
        await _openDownloadPage(downloadUrl);
      }
      return;
    }
    showOmniFeedback(context, message);
  }

  Future<void> _openDownloadPage(String url) async {
    // Web 经条件导入新开下载页；弹窗拦截时退回展示地址，与桌面端一致。
    if (kIsWeb && openDownloadUrl(url)) {
      return;
    }
    if (!mounted) {
      return;
    }
    showOmniFeedback(
      context,
      '${AppLocalizations.of(context).settingsOpenDownloadPage}: $url',
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
