import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/appearance/application/appearance_controller.dart';
import 'package:omninest/app/appearance/application/font_scale_controller.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/locale/application/locale_controller.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/mobile_layout_tokens.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/config/file_size_thresholds.dart';
import 'package:omninest/core/auth/user_capabilities.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/core/widgets/responsive_breakpoints.dart';
import 'package:omninest/core/widgets/workstation_controls.dart';
import 'package:omninest/core/widgets/workstation_dialog.dart';
import 'package:omninest/core/window/desktop_close_action.dart';
import 'package:omninest/core/window/desktop_close_behavior_controller.dart';
import 'package:omninest/features/backdrop/backdrop_ui.dart';
import 'package:omninest/features/notifications/application/notification_controller.dart';
import 'package:omninest/features/notifications/application/notification_foreground_presenter.dart';
import 'package:omninest/features/notifications/application/notification_preferences_controller.dart';
import 'package:omninest/features/notifications/application/notification_type_controller.dart';
import 'package:omninest/features/notifications/domain/notification_preferences.dart';
import 'package:omninest/features/profile/application/profile_controller.dart';
import 'package:omninest/features/profile/presentation/widgets/change_password_dialog.dart';
import 'package:omninest/features/profile/presentation/widgets/profile_account_panel.dart';
import 'package:omninest/features/profile/presentation/widgets/profile_appearance_panel.dart';
import 'package:omninest/features/profile/presentation/widgets/profile_section_card.dart';
import 'package:omninest/features/profile/presentation/widgets/profile_server_panel.dart';
import 'package:omninest/features/profile/presentation/widgets/profile_desktop_preferences.dart';
import 'package:omninest/features/profile/presentation/widgets/profile_desktop_shell.dart';
import 'package:omninest/features/profile/presentation/widgets/profile_mobile_content.dart';
import 'package:omninest/features/profile/presentation/widgets/profile_session_management_panel.dart';
import 'package:omninest/features/profile/presentation/widgets/profile_two_factor_card.dart';
import 'package:omninest/features/profile/presentation/widgets/profile_support_panels.dart';
import 'package:omninest/features/portal/application/weather_preferences_controller.dart';
import 'package:omninest/features/portal/application/weather_provider.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/feedback/omni_feedback.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({this.initialSection, super.key});

  final String? initialSection;

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  late ProfileSection _selectedSection;

  @override
  void initState() {
    super.initState();
    _selectedSection = ProfileSection.parse(widget.initialSection);
  }

  @override
  void didUpdateWidget(ProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSection != widget.initialSection) {
      _selectedSection = ProfileSection.parse(widget.initialSection);
    }
  }

  Future<bool> _saveProfile(String displayName, String email) async {
    final l10n = AppLocalizations.of(context);
    try {
      await ref
          .read(profileCommandServiceProvider)
          .updateProfile(displayName: displayName, email: email);
      if (!mounted) {
        return true;
      }
      ref.invalidate(authSessionProvider);
      _showMessage(l10n.profileUpdateSuccess);
      return true;
    } catch (_) {
      // 失败由编辑窗口内联提示，页面不再叠加 toast。
      return false;
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    final l10n = AppLocalizations.of(context);
    final profileService = ref.read(profileCommandServiceProvider);
    final result = await FilePicker.pickFiles(type: FileType.image);
    if (!mounted) {
      return;
    }
    if (result.isEmpty) return;
    final file = result.first;
    final bytes = await file.readAsBytes();
    if (!mounted) {
      return;
    }
    if (bytes.isEmpty) return;
    final extension = file.extension?.toLowerCase();
    if (extension == null ||
        !['jpg', 'jpeg', 'png', 'webp'].contains(extension)) {
      _showMessage(l10n.profileAvatarFormatError);
      return;
    }
    if (bytes.length > FileSizeThresholds.avatarUploadMaxBytes) {
      _showMessage(l10n.profileAvatarSizeError);
      return;
    }
    try {
      await profileService.uploadAvatar(bytes, file.name);
      if (!mounted) {
        return;
      }
      ref.invalidate(authSessionProvider);
      _showMessage(l10n.profileAvatarSuccess);
    } catch (_) {
      _showMessage(l10n.profileAvatarFailed);
    }
  }

  Future<void> _updateNotificationPreferences(
    NotificationPreferences preferences,
  ) async {
    final preferencesController = ref.read(
      notificationPreferencesProvider.notifier,
    );
    try {
      await preferencesController.save(preferences);
    } catch (_) {
      if (!mounted) return;
      _showMessage(AppLocalizations.of(context).profileNotificationSaveFailed);
    }
  }

  Future<void> _updateWeatherCity(String city) async {
    final l10n = AppLocalizations.of(context);
    final locationController = ref.read(weatherLocationProvider.notifier);
    try {
      await locationController.save(city);
      if (!mounted) {
        return;
      }
      ref.invalidate(realtimeWeatherProvider);
    } catch (error) {
      _showMessage(
        l10n.profileWeatherCitySaveFailed(
          describeUserFacingError(error, l10n: l10n).message,
        ),
      );
    }
  }

  Future<void> _showWeatherCityEditor() async {
    final l10n = AppLocalizations.of(context);
    var city = ref.read(weatherLocationProvider).asData?.value ?? '';
    final result = await showWorkstationDialog<String>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(l10n.profileWeatherCity),
            content: TextFormField(
              initialValue: city,
              autofocus: true,
              decoration: InputDecoration(
                hintText: l10n.profileWeatherCityPlaceholder,
              ),
              onChanged: (value) => city = value,
              onFieldSubmitted: (value) => Navigator.pop(dialogContext, value),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(l10n.coreCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, city),
                child: Text(l10n.profileWeatherCitySave),
              ),
            ],
          ),
    );
    if (!mounted) {
      return;
    }
    if (result != null) await _updateWeatherCity(result);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final user = ref.watch(authSessionProvider).asData?.value.user;
    final displayName =
        user?.displayName ?? user?.username ?? l10n.profileUnknownUser;
    final username = user?.username ?? '';
    final email = user?.email ?? l10n.profileEmailNotSet;
    final userId = user?.id ?? '';
    final role = user?.role ?? 'MEMBER';
    final avatarUrl = user?.avatarUrl;
    final unreadCount = ref.watch(unreadCountProvider);
    final weatherCity = ref.watch(weatherLocationProvider).asData?.value;
    final themeMode = ref.watch(appearanceControllerProvider);
    final languageCode = ref.watch(localeControllerProvider);
    final fontScalePreset = ref.watch(fontScaleControllerProvider);
    // 关闭窗口行为是桌面托盘专属设置，仅在桌面平台读取与展示。
    final rememberedCloseAction =
        isDesktopPlatform
            ? ref.watch(desktopCloseBehaviorProvider).asData?.value
            : null;

    // 个人中心为根 Navigator 承载的顶层路由，屏幕宽即可用画布宽。
    if (MediaQuery.sizeOf(context).width <
        ResponsiveBreakpoints.workbenchRail) {
      return Scaffold(
        backgroundColor: context.mobileColors.pageMask,
        appBar: AppBar(
          backgroundColor: context.mobileColors.pageMask.withValues(
            alpha: 0.96,
          ),
          foregroundColor: context.mobileColors.textPrimary,
          leading: IconButton(
            onPressed: () => context.go('/portal'),
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: l10n.profileBackTooltip,
          ),
          title: Text(l10n.profileTitle),
          actions: [
            IconButton(
              onPressed: () => context.push('/notifications'),
              icon: const Icon(Icons.notifications_none_rounded),
              tooltip: l10n.notificationTitle,
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: ProfileMobileContent(
          displayName: displayName,
          username: username,
          email: email,
          role: role,
          avatarUrl: avatarUrl,
          unreadCount: unreadCount,
          weatherCity: weatherCity,
          themeMode: themeMode,
          languageCode: languageCode,
          fontScalePreset: fontScalePreset,
          onThemeChanged:
              ref.read(appearanceControllerProvider.notifier).setThemeMode,
          onLanguageChanged:
              ref.read(localeControllerProvider.notifier).setLanguage,
          onFontScaleChanged:
              (preset) => unawaited(
                ref
                    .read(fontScaleControllerProvider.notifier)
                    .setPreset(preset),
              ),
          onEditAvatar: _pickAndUploadAvatar,
          onEditWeatherCity: _showWeatherCityEditor,
        ),
      );
    }

    return ProfileDesktopShell(
      selectedSection: _selectedSection,
      onSectionSelected:
          (section) => setState(() => _selectedSection = section),
      displayName: displayName,
      username: username,
      role: role,
      avatarUrl: avatarUrl,
      onBack: () => context.go('/portal'),
      onNotifications: () => context.push('/notifications'),
      onSignOut: ref.read(authSessionProvider.notifier).clearSession,
      child: _desktopPanel(
        displayName: displayName,
        username: username,
        email: email,
        userId: userId,
        role: role,
        avatarUrl: avatarUrl,
        unreadCount: unreadCount,
        weatherCity: weatherCity,
        themeMode: themeMode,
        languageCode: languageCode,
        fontScalePreset: fontScalePreset,
        rememberedCloseAction: rememberedCloseAction,
      ),
    );
  }

  Widget _desktopPanel({
    required String displayName,
    required String username,
    required String email,
    required String userId,
    required String role,
    required String? avatarUrl,
    required int unreadCount,
    required String? weatherCity,
    required ThemeMode themeMode,
    required String languageCode,
    required FontScalePreset fontScalePreset,
    required DesktopCloseAction? rememberedCloseAction,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _SectionHeader(section: _selectedSection),
        switch (_selectedSection) {
          ProfileSection.account => LayoutBuilder(
            builder: (context, constraints) {
              final account = ProfileAccountPanel(
                displayName: displayName,
                username: username,
                email: email,
                userId: userId,
                role: role,
                avatarUrl: avatarUrl,
                unreadCount: unreadCount,
                onEditAvatar: _pickAndUploadAvatar,
                canEditProfile:
                    ref.watch(userCapabilitiesProvider).canManageAccount,
                onSaveProfile: _saveProfile,
              );
              final weather = ProfileWeatherCityCard(
                city: weatherCity,
                onChanged: _updateWeatherCity,
              );
              if (constraints.maxWidth < 980) {
                return Column(
                  children: [account, const SizedBox(height: 18), weather],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: account),
                  const SizedBox(width: 20),
                  SizedBox(width: 340, child: weather),
                ],
              );
            },
          ),
          ProfileSection.appearance => ProfileAppearancePanel(
            themeMode: themeMode,
            languageCode: languageCode,
            fontScalePreset: fontScalePreset,
            onThemeChanged:
                ref.read(appearanceControllerProvider.notifier).setThemeMode,
            onLanguageChanged:
                ref.read(localeControllerProvider.notifier).setLanguage,
            onFontScaleChanged:
                (preset) => unawaited(
                  ref
                      .read(fontScaleControllerProvider.notifier)
                      .setPreset(preset),
                ),
            onBackdropSettings: _showBackdropSettings,
            rememberedCloseAction: rememberedCloseAction,
            onCloseBehaviorChanged:
                isDesktopPlatform
                    ? (value) => unawaited(
                      ref
                          .read(desktopCloseBehaviorProvider.notifier)
                          .setAction(value),
                    )
                    : null,
          ),
          ProfileSection.notifications => _notificationPanel(),
          ProfileSection.security => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ProfileSectionCard(
                title: AppLocalizations.of(context).profileCredentialsTitle,
                child: Column(
                  children: [
                    ProfileSecurityActionsPanel(
                      onChangePassword: _showChangePassword,
                    ),
                    Divider(
                      height: 20,
                      thickness: 1,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    const ProfileTwoFactorCard(),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const ProfileSessionManagementPanel(),
            ],
          ),
          ProfileSection.server => const ProfileServerPanel(),
          ProfileSection.about => const ProfileAboutPanel(),
        },
      ],
    );
  }

  Widget _notificationPanel() {
    final l10n = AppLocalizations.of(context);
    final preferences = ref.watch(notificationPreferencesProvider);
    final types = ref.watch(notificationTypesProvider);
    final scheme = Theme.of(context).colorScheme;
    Widget plainCard({
      required Widget child,
      EdgeInsetsGeometry padding = const EdgeInsets.all(20),
    }) {
      return Container(
        padding: padding,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: child,
      );
    }

    return preferences.when(
      loading:
          () => plainCard(
            padding: const EdgeInsets.all(28),
            child: const LinearProgressIndicator(minHeight: 2),
          ),
      error:
          (error, _) => plainCard(
            child: Row(
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.profileLoadFailed(
                      describeUserFacingError(error, l10n: l10n).message,
                    ),
                  ),
                ),
                WorkstationIconButton(
                  onPressed:
                      () => ref.invalidate(notificationPreferencesProvider),
                  icon: Icons.refresh_rounded,
                  tooltip: l10n.coreRetry,
                ),
              ],
            ),
          ),
      data: (value) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _ForegroundToastToggleCard(),
            const SizedBox(height: 16),
            ProfileNotificationSettingsCard(
              typesAsync: types,
              prefs: value,
              onChanged: _updateNotificationPreferences,
            ),
          ],
        );
      },
    );
  }

  Future<void> _showBackdropSettings() {
    return showAppBackdropSettings(context);
  }

  Future<void> _showChangePassword() {
    return ChangePasswordDialog.show(context);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    showOmniFeedback(context, message);
  }
}

/// 前台新通知提示开关（设备级本地偏好，默认开启）。
class _ForegroundToastToggleCard extends ConsumerWidget {
  const _ForegroundToastToggleCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final enabled = ref.watch(notificationForegroundToastEnabledProvider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.notificationForegroundToastToggle,
                  style: TextStyle(
                    fontSize: AppTypography.bodyMedium,
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.notificationForegroundToastToggleSubtitle,
                  style: TextStyle(
                    fontSize: AppTypography.labelSmall,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          WorkstationSwitch(
            value: enabled.asData?.value ?? true,
            onChanged: (value) {
              unawaited(
                ref
                    .read(notificationForegroundPreferenceStoreProvider)
                    .saveEnabled(value)
                    .then((_) {
                      if (context.mounted) {
                        ref.invalidate(
                          notificationForegroundToastEnabledProvider,
                        );
                      }
                    }),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 分区页头：标题 + 副标题，与内容卡之间留白。
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.section});

  final ProfileSection section;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (title, subtitle) = switch (section) {
      ProfileSection.account => (
        l10n.profileHeaderAccount,
        l10n.profileSectionAccountSubtitle,
      ),
      ProfileSection.appearance => (
        l10n.profileHeaderAppearance,
        l10n.profileSectionAppearanceSubtitle,
      ),
      ProfileSection.notifications => (
        l10n.profileHeaderNotifications,
        l10n.profileSectionNotificationsSubtitle,
      ),
      ProfileSection.security => (
        l10n.profileHeaderSecurity,
        l10n.profileSectionSecuritySubtitle,
      ),
      ProfileSection.server => (
        l10n.profileHeaderServer,
        l10n.profileSectionServerSubtitle,
      ),
      ProfileSection.about => (
        l10n.profileHeaderAbout,
        l10n.profileSectionAboutSubtitle,
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: AppTypography.titleLarge,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: AppTypography.bodySmall,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
