import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/appearance/application/appearance_controller.dart';
import 'package:omninest/app/appearance/application/font_scale_controller.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/locale/application/locale_controller.dart';
import 'package:omninest/app/theme/global_theme_colors.dart';
import 'package:omninest/app/theme/mobile_layout_tokens.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/widgets/workbench_panel.dart';
import 'package:omninest/features/backdrop/backdrop_ui.dart';
import 'package:omninest/features/notifications/application/notification_controller.dart';
import 'package:omninest/features/notifications/application/notification_preferences_controller.dart';
import 'package:omninest/features/notifications/application/notification_type_controller.dart';
import 'package:omninest/features/notifications/domain/notification_preferences.dart';
import 'package:omninest/features/profile/application/profile_controller.dart';
import 'package:omninest/features/profile/presentation/widgets/change_password_dialog.dart';
import 'package:omninest/features/profile/presentation/widgets/profile_account_panel.dart';
import 'package:omninest/features/profile/presentation/widgets/profile_appearance_panel.dart';
import 'package:omninest/features/profile/presentation/widgets/profile_desktop_preferences.dart';
import 'package:omninest/features/profile/presentation/widgets/profile_desktop_shell.dart';
import 'package:omninest/features/profile/presentation/widgets/profile_mobile_content.dart';
import 'package:omninest/features/profile/presentation/widgets/profile_session_management_panel.dart';
import 'package:omninest/features/profile/presentation/widgets/profile_support_panels.dart';
import 'package:omninest/features/portal/application/weather_preferences_controller.dart';
import 'package:omninest/features/portal/application/weather_provider.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({this.initialSection, super.key});

  final String? initialSection;

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  NotificationPreferences? _notificationPreferences;
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

  Future<void> _pickAndUploadAvatar() async {
    final l10n = AppLocalizations.of(context);
    final profileService = ref.read(profileCommandServiceProvider);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (!mounted) {
      return;
    }
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;
    final extension = file.extension?.toLowerCase();
    if (extension == null ||
        !['jpg', 'jpeg', 'png', 'webp'].contains(extension)) {
      _showMessage(l10n.profileAvatarFormatError);
      return;
    }
    if (file.bytes!.length > 5 * 1024 * 1024) {
      _showMessage(l10n.profileAvatarSizeError);
      return;
    }
    try {
      await profileService.uploadAvatar(file.bytes!, file.name);
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
    final previous = _notificationPreferences;
    final preferencesController = ref.read(
      notificationPreferencesProvider.notifier,
    );
    setState(() => _notificationPreferences = preferences);
    try {
      await preferencesController.save(preferences);
    } catch (_) {
      if (!mounted) return;
      setState(() => _notificationPreferences = previous);
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
      _showMessage(l10n.profileWeatherCitySaveFailed(error.toString()));
    }
  }

  Future<void> _showWeatherCityEditor() async {
    final l10n = AppLocalizations.of(context);
    var city = ref.read(weatherLocationProvider).asData?.value ?? '';
    final result = await showDialog<String>(
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

    if (MediaQuery.sizeOf(context).width < 860) {
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
  }) {
    return switch (_selectedSection) {
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
              ref.read(fontScaleControllerProvider.notifier).setPreset(preset),
            ),
        onBackdropSettings: _showBackdropSettings,
      ),
      ProfileSection.notifications => _notificationPanel(),
      ProfileSection.security => Column(
        children: [
          ProfileSecurityActionsPanel(onChangePassword: _showChangePassword),
          const SizedBox(height: 18),
          const ProfileSessionManagementPanel(),
        ],
      ),
      ProfileSection.about => const ProfileAboutPanel(),
    };
  }

  Widget _notificationPanel() {
    final l10n = AppLocalizations.of(context);
    final preferences = ref.watch(notificationPreferencesProvider);
    final types = ref.watch(notificationTypesProvider);
    return preferences.when(
      loading:
          () => const WorkbenchPanel(
            padding: EdgeInsets.all(28),
            child: LinearProgressIndicator(),
          ),
      error:
          (error, _) => WorkbenchPanel(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded),
                const SizedBox(width: 12),
                Expanded(child: Text(l10n.profileLoadFailed(error.toString()))),
                IconButton(
                  onPressed:
                      () => ref.invalidate(notificationPreferencesProvider),
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: l10n.coreRetry,
                ),
              ],
            ),
          ),
      data: (value) {
        _notificationPreferences ??= value;
        return ProfileNotificationSettingsCard(
          typesAsync: types,
          prefs: _notificationPreferences!,
          onChanged: _updateNotificationPreferences,
        );
      },
    );
  }

  Future<void> _showBackdropSettings() {
    final colors = context.globalColors;
    return showAppBackdropSettings(
      context,
      palette: AppBackdropPalette(
        text: colors.onSurface,
        muted: colors.onSurfaceVariant,
        accent: colors.primary,
        accentAlt: colors.tertiary,
      ),
    );
  }

  Future<void> _showChangePassword() {
    return showDialog<void>(
      context: context,
      builder: (_) => const ChangePasswordDialog(),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
