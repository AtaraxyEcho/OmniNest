import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omninest/app/appearance/application/appearance_controller.dart';
import 'package:omninest/app/appearance/application/font_scale_controller.dart';
import 'package:omninest/app/desktop/desktop_backdrop_scope.dart';
import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_router_scope.dart';
import 'package:omninest/app/desktop/desktop_shell_state.dart';
import 'package:omninest/app/desktop/desktop_toast.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_dialogs.dart';
import 'package:omninest/app/desktop/widgets/desktop_fields.dart';
import 'package:omninest/app/desktop/widgets/desktop_surfaces.dart';
import 'package:omninest/app/environment_providers.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/locale/application/locale_controller.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_palette.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/config/file_size_thresholds.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/version/app_version_api.dart';
import 'package:omninest/core/version/app_version_controller.dart';
import 'package:omninest/core/utils/file_size_formatter.dart';
import 'package:omninest/features/backdrop/backdrop_ui.dart';
import 'package:omninest/features/files/file_dashboard.dart';
import 'package:omninest/features/notifications/application/notification_preferences_controller.dart';
import 'package:omninest/features/notifications/domain/notification_preferences.dart';
import 'package:omninest/features/profile/application/profile_controller.dart';
import 'package:omninest/features/profile/domain/user_session.dart';
import 'package:omninest/features/portal/portal_weather.dart';
import 'package:omninest/features/portal/application/weather_provider.dart'
    show weatherApiProvider;
import 'package:omninest/features/portal/data/weather_api.dart'
    show WeatherCitySuggestion;
import 'package:omninest/platform/file_pick.dart';

part 'desktop_settings_backdrop.dart';
part 'desktop_settings_more.dart';
part 'desktop_settings_weather.dart';

/// 桌面设置页（样例 `Settings.tsx`）。
///
/// 分区顺序与样例逐项一致：Profile · Appearance · Backdrop library ·
/// Notifications · Security · Storage · Connected services · About & updates。
enum DesktopSettingsSection {
  profile,
  appearance,
  backdrop,
  notifications,
  security,
  storage,
  services,
  about,
}

class DesktopSettingsPage extends ConsumerStatefulWidget {
  const DesktopSettingsPage({this.initialSection, super.key});

  final String? initialSection;

  @override
  ConsumerState<DesktopSettingsPage> createState() =>
      _DesktopSettingsPageState();
}

class _DesktopSettingsPageState extends ConsumerState<DesktopSettingsPage> {
  late DesktopSettingsSection _section = switch (widget.initialSection) {
    'storage' || 'storageStats' => DesktopSettingsSection.storage,
    'profile' || 'account' => DesktopSettingsSection.profile,
    'backdrop' || 'wallpaper' => DesktopSettingsSection.backdrop,
    'notifications' => DesktopSettingsSection.notifications,
    'security' || 'sessions' => DesktopSettingsSection.security,
    'services' || 'connected' => DesktopSettingsSection.services,
    'about' || 'update' => DesktopSettingsSection.about,
    'appearance' || 'theme' => DesktopSettingsSection.appearance,
    _ => DesktopSettingsSection.profile,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final user = ref.watch(authSessionProvider).asData?.value.user;
    final name =
        (user?.displayName?.trim().isNotEmpty ?? false)
            ? user!.displayName!.trim()
            : (user?.username ?? '');

    final labels = <DesktopSettingsSection, String>{
      DesktopSettingsSection.appearance: l10n.desktopAppearance,
      DesktopSettingsSection.profile: l10n.desktopAccount,
      DesktopSettingsSection.backdrop: l10n.desktopBackdropLibrary,
      DesktopSettingsSection.notifications: l10n.settingsNotification,
      DesktopSettingsSection.security: l10n.desktopSecuritySessions,
      DesktopSettingsSection.services: l10n.desktopConnectedServices,
      DesktopSettingsSection.storage: l10n.desktopStorage,
      DesktopSettingsSection.about: l10n.settingsAbout,
    };
    final icons = <DesktopSettingsSection, IconData>{
      DesktopSettingsSection.appearance: DesktopIcons.sparkle,
      DesktopSettingsSection.profile: DesktopIcons.user,
      DesktopSettingsSection.backdrop: DesktopIcons.wallpaper,
      DesktopSettingsSection.notifications: DesktopIcons.bell,
      DesktopSettingsSection.security: DesktopIcons.shield,
      DesktopSettingsSection.services: DesktopIcons.link,
      DesktopSettingsSection.storage: DesktopIcons.cloud,
      DesktopSettingsSection.about: DesktopIcons.info,
    };

    return SingleChildScrollView(
      child: DesktopPage(
        topPadding: DesktopMetrics.pageTopPaddingCompact,
        children: [
          DesktopPageHead(
            eyebrow:
                '${name.isEmpty ? l10n.desktopAccount : name} · ${l10n.desktopOwner}'
                    .toUpperCase(),
            title: l10n.desktopNavSettings,
            subtitle: l10n.desktopSettingsSubtitle,
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 220,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final section in DesktopSettingsSection.values)
                      _NavRow(
                        label: labels[section] ?? '',
                        icon: icons[section]!,
                        active: _section == section,
                        onTap: () => setState(() => _section = section),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 40),
              // `desktop.css:470` 的 220px / minmax(0,760px) / 40px：
              // 内容列最多 760，剩余宽度留白而不是把字段拉满。
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final bodyWidth =
                        constraints.maxWidth > 760
                            ? 760.0
                            : constraints.maxWidth;
                    return SizedBox(
                      width: bodyWidth,
                      child: KeyedSubtree(
                        key: ValueKey<DesktopSettingsSection>(_section),
                        child: DesktopRise(
                          child: switch (_section) {
                            DesktopSettingsSection.appearance =>
                              const _AppearanceSection(),
                            DesktopSettingsSection.backdrop =>
                              const _BackdropSection(),
                            DesktopSettingsSection.profile => _ProfileSection(
                              name: name,
                              email: user?.email ?? '',
                              role: user?.role ?? '',
                              avatarUrl: user?.avatarUrl,
                              skin: skin,
                            ),
                            DesktopSettingsSection.notifications =>
                              const _NotificationsSection(),
                            DesktopSettingsSection.security =>
                              const _SecuritySection(),
                            DesktopSettingsSection.services =>
                              const _ServicesSection(),
                            DesktopSettingsSection.storage =>
                              const _StorageSection(),
                            DesktopSettingsSection.about =>
                              const _AboutSection(),
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: DesktopHover(
        builder:
            (context, hovered) => GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: DesktopMotion.of(context, DesktopMotion.fast),
                height: DesktopMetrics.navItemHeight,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color:
                      active
                          ? skin.raise2
                          : hovered
                          ? skin.raise
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(
                    DesktopMetrics.radiusButton,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      icon,
                      size: DesktopMetrics.iconSmall,
                      color: active ? skin.accent : skin.text2,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DesktopType.navItem(
                          active ? skin.text : skin.text2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ),
    );
  }
}

class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final appearance = ref.watch(desktopAppearanceProvider);
    final controller = ref.read(desktopAppearanceProvider.notifier);
    final themeMode = ref.watch(appearanceControllerProvider);
    final locale = ref.watch(localeControllerProvider);
    final fontScale = ref.watch(fontScaleControllerProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Card(
          title: l10n.desktopTheme,
          child: Row(
            children: [
              for (final (mode, label) in <(ThemeMode, String)>[
                (ThemeMode.dark, l10n.desktopThemeDark),
                (ThemeMode.light, l10n.desktopThemeLight),
                (ThemeMode.system, l10n.desktopThemeSystem),
              ]) ...[
                Expanded(
                  child: _ThemeCard(
                    mode: mode,
                    label: label,
                    selected: themeMode == mode,
                    onTap:
                        () => ref
                            .read(appearanceControllerProvider.notifier)
                            .setThemeMode(mode),
                  ),
                ),
                if (mode != ThemeMode.system) const SizedBox(width: 12),
              ],
            ],
          ),
        ),
        _Card(
          title: l10n.desktopAccent,
          subtitle: l10n.desktopAccentHint,
          child: Wrap(
            spacing: 12,
            children: [
              for (final accent in DesktopAccent.values)
                _AccentSwatch(
                  accent: accent,
                  label: _accentLabel(l10n, accent),
                  selected: appearance.accent == accent,
                  onTap: () => controller.setAccent(accent),
                ),
            ],
          ),
        ),
        _Card(
          title: l10n.desktopLanguageAndText,
          child: Column(
            children: [
              _SettingsPreferenceRow(
                title: l10n.desktopLanguage,
                hint: l10n.desktopLanguageHint,
                child: DesktopSeg<String>(
                  options: const ['en', 'zh'],
                  value: locale,
                  small: true,
                  labelOf:
                      (code) =>
                          code == 'zh'
                              ? l10n.desktopLanguageChinese
                              : l10n.settingsLanguageEnglish,
                  onChanged:
                      (code) => _updateDesktopLanguage(context, ref, code),
                ),
              ),
              _SettingsPreferenceRow(
                title: l10n.desktopTextSize,
                hint: l10n.desktopTextSizeHint,
                child: SizedBox(
                  width: 250,
                  child: Row(
                    children: [
                      Expanded(
                        child: DesktopSlider(
                          value:
                              ((fontScale.percent ?? 100) - 85)
                                  .clamp(0, 40)
                                  .toDouble(),
                          max: 40,
                          onChanged: (value) {
                            final percent = 85 + (value / 5).round() * 5;
                            ref
                                .read(fontScaleControllerProvider.notifier)
                                .setPreset(
                                  FontScalePreset.fromPercent(percent),
                                );
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 48,
                        child: Text(
                          l10n.desktopPercentValue(fontScale.percent ?? 100),
                          textAlign: TextAlign.right,
                          style: DesktopType.numeric(
                            DesktopSkin.of(context).text3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        _Card(
          title: l10n.desktopAtmosphere,
          child: Column(
            children: [
              _SettingsPreferenceRow(
                title: l10n.desktopAmbientLight,
                hint: l10n.desktopAmbientHint,
                child: SizedBox(
                  width: 250,
                  child: Row(
                    children: [
                      Expanded(
                        child: DesktopSlider(
                          value: appearance.ambient,
                          max: 100,
                          onChanged: controller.setAmbient,
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 48,
                        child: Text(
                          l10n.desktopPercentValue(appearance.ambient.round()),
                          textAlign: TextAlign.right,
                          style: DesktopType.numeric(
                            DesktopSkin.of(context).text3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _SettingsPreferenceRow(
                title: l10n.desktopReduceMotion,
                hint: l10n.desktopReduceMotionHint,
                child: DesktopToggle(
                  value: appearance.reduceMotion,
                  onChanged: controller.setReduceMotion,
                  label: l10n.desktopReduceMotion,
                ),
              ),
              _SettingsPreferenceRow(
                title: l10n.desktopCompactDensity,
                hint: l10n.desktopCompactHint,
                child: DesktopToggle(
                  value: appearance.compact,
                  onChanged: controller.setCompact,
                  label: l10n.desktopCompactDensity,
                ),
              ),
            ],
          ),
        ),
        const _WeatherSettingsCard(),
      ],
    );
  }

  String _accentLabel(AppLocalizations l10n, DesktopAccent accent) {
    return switch (accent) {
      DesktopAccent.sage => l10n.desktopAccentSage,
      DesktopAccent.mist => l10n.desktopAccentMist,
      DesktopAccent.copper => l10n.desktopAccentCopper,
      DesktopAccent.iris => l10n.desktopAccentIris,
    };
  }
}

class _SettingsPreferenceRow extends StatelessWidget {
  const _SettingsPreferenceRow({
    required this.title,
    required this.hint,
    required this.child,
  });

  final String title;
  final String hint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: skin.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: DesktopType.denseStrong(skin.text)),
                const SizedBox(height: 2),
                Text(hint, style: DesktopType.caption(skin.text3)),
              ],
            ),
          ),
          const SizedBox(width: 20),
          child,
        ],
      ),
    );
  }
}

Future<void> _updateDesktopLanguage(
  BuildContext context,
  WidgetRef ref,
  String code,
) async {
  try {
    await ref.read(localeControllerProvider.notifier).setLanguage(code);
    if (!context.mounted) return;
    showDesktopToast(
      context,
      AppLocalizations.of(context).desktopLanguageChanged,
      icon: DesktopIcons.check,
    );
  } on Object catch (error) {
    if (!context.mounted) return;
    final l10n = AppLocalizations.of(context);
    showDesktopToast(
      context,
      failureToast(l10n, l10n.desktopLanguage, error),
      kind: DesktopToastKind.error,
      icon: DesktopIcons.info,
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.mode,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final ThemeMode mode;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final dark =
        mode == ThemeMode.dark ||
        (mode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);
    final preview = dark ? DesktopPalette.bgDark : DesktopPalette.bgLight;
    final line =
        dark
            ? Colors.white.withValues(alpha: 0.14)
            : Colors.black.withValues(alpha: 0.12);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: DesktopMotion.of(context, DesktopMotion.fast),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? skin.raise2 : skin.raise,
          borderRadius: BorderRadius.circular(DesktopMetrics.radiusCard),
          border: Border.all(color: selected ? skin.accent : skin.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 76,
              decoration: BoxDecoration(
                color: preview,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: line),
              ),
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(width: 44, height: 6, color: line),
                  const SizedBox(height: 6),
                  Container(width: 26, height: 4, color: line),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(label, style: DesktopType.bodyStrong(skin.text)),
          ],
        ),
      ),
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.accent,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final DesktopAccent accent;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: skin.isDark ? accent.dark : accent.light,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? skin.text : skin.line2,
                width: selected ? 2 : 1,
              ),
            ),
            child:
                selected
                    ? Icon(DesktopIcons.check, size: 13, color: skin.accentInk)
                    : null,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: DesktopType.dense(selected ? skin.text : skin.text2),
          ),
        ],
      ),
    );
  }
}

class _ProfileSection extends ConsumerStatefulWidget {
  const _ProfileSection({
    required this.name,
    required this.email,
    required this.role,
    required this.avatarUrl,
    required this.skin,
  });

  final String name;
  final String email;
  final String role;
  final String? avatarUrl;
  final DesktopSkin skin;

  @override
  ConsumerState<_ProfileSection> createState() => _ProfileSectionState();
}

class _ProfileSectionState extends ConsumerState<_ProfileSection> {
  late final TextEditingController _name = TextEditingController(
    text: widget.name,
  );
  late final TextEditingController _email = TextEditingController(
    text: widget.email,
  );
  late String _savedName = widget.name;
  late String _savedEmail = widget.email;
  bool _dirty = false;
  bool _saving = false;
  bool _avatarBusy = false;

  @override
  void didUpdateWidget(_ProfileSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dirty &&
        (oldWidget.name != widget.name || oldWidget.email != widget.email)) {
      _savedName = widget.name;
      _savedEmail = widget.email;
      _name.text = widget.name;
      _email.text = widget.email;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = widget.skin;
    final host =
        Uri.tryParse(ref.read(appEnvironmentProvider)?.apiBaseUrl ?? '')?.host;
    final name = _name.text.trim();
    final email = _email.text.trim();
    final invalidName = name.isEmpty || name.length > 40;
    final invalidEmail = !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);
    return _Card(
      title: l10n.desktopAccount,
      subtitle: l10n.profileAccountSubtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 34,
                backgroundColor: widget.skin.accent,
                backgroundImage:
                    widget.avatarUrl == null || widget.avatarUrl!.isEmpty
                        ? null
                        : NetworkImage(widget.avatarUrl!),
                child:
                    widget.avatarUrl == null || widget.avatarUrl!.isEmpty
                        ? Text(
                          name.isEmpty
                              ? '·'
                              : name.characters.first.toUpperCase(),
                          style: DesktopType.panelTitle(widget.skin.accentInk),
                        )
                        : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: DesktopType.panelTitle(widget.skin.text)),
                    const SizedBox(height: 2),
                    Text(
                      email.isEmpty ? '—' : email,
                      style: DesktopType.dense(widget.skin.text3),
                    ),
                  ],
                ),
              ),
              DesktopButton(
                label: l10n.profileChangeAvatar,
                icon: DesktopIcons.upload,
                variant: DesktopButtonVariant.soft,
                busy: _avatarBusy,
                onPressed: _avatarBusy ? null : _pickAvatar,
              ),
              if (widget.avatarUrl?.isNotEmpty == true) ...[
                const SizedBox(width: 8),
                DesktopButton(
                  label: l10n.profileRemoveAvatar,
                  icon: DesktopIcons.trash,
                  variant: DesktopButtonVariant.ghost,
                  busy: _avatarBusy,
                  onPressed: _avatarBusy ? null : _removeAvatar,
                ),
              ],
            ],
          ),
          const SizedBox(height: 18),
          Divider(height: 1, color: skin.line),
          const SizedBox(height: 14),
          DesktopTextField(
            keyName: 'desktop-profile-display-name',
            controller: _name,
            label: l10n.profileDisplayNameField,
            maxLength: 40,
            error: invalidName ? l10n.desktopProfileDisplayNameInvalid : null,
            onChanged: (_) => setState(() => _dirty = true),
          ),
          const SizedBox(height: 14),
          DesktopTextField(
            keyName: 'desktop-profile-email',
            controller: _email,
            label: l10n.profileEmailField,
            error: invalidEmail ? l10n.profileEmailInvalid : null,
            onChanged: (_) => setState(() => _dirty = true),
          ),
          const SizedBox(height: 8),
          _KvRow(
            label: l10n.desktopRole,
            value: widget.role.isEmpty ? '—' : widget.role,
          ),
          _KvRow(
            label: l10n.desktopServer,
            value: (host == null || host.isEmpty) ? '—' : host,
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              DesktopButton(
                label: l10n.profileResetChanges,
                onPressed: _dirty ? _reset : null,
              ),
              const SizedBox(width: 8),
              DesktopButton(
                label: l10n.profileSaveChanges,
                icon: DesktopIcons.check,
                variant: DesktopButtonVariant.primary,
                busy: _saving,
                onPressed:
                    !_dirty || _saving || invalidName || invalidEmail
                        ? null
                        : _save,
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _reset() {
    setState(() {
      _name.text = _savedName;
      _email.text = _savedEmail;
      _dirty = false;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final l10n = AppLocalizations.of(context);
    try {
      await ref
          .read(profileCommandServiceProvider)
          .updateProfile(
            displayName: _name.text.trim(),
            email: _email.text.trim(),
          );
      if (!mounted) return;
      await ref.read(authSessionProvider.notifier).reloadProfile();
      if (!mounted) return;
      setState(() {
        _savedName = _name.text.trim();
        _savedEmail = _email.text.trim();
        _dirty = false;
      });
      showDesktopToast(
        context,
        l10n.profileUpdateSuccess,
        icon: DesktopIcons.check,
      );
    } on Object catch (error) {
      if (mounted) {
        showDesktopToast(
          context,
          failureToast(l10n, l10n.profileSaveChanges, error),
          kind: DesktopToastKind.error,
          icon: DesktopIcons.info,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickAvatar() async {
    final l10n = AppLocalizations.of(context);
    try {
      final selected = await FilePick.pickImages(
        dialogTitle: l10n.profileChangeAvatar,
      );
      if (!mounted || selected.isEmpty) return;
      final file = selected.first;
      final length = await file.length();
      if (!mounted) return;
      if (length != null &&
          length > FileSizeThresholds.desktopAvatarUploadMaxBytes) {
        showDesktopToast(
          context,
          l10n.desktopProfileAvatarSizeError,
          kind: DesktopToastKind.error,
        );
        return;
      }
      final extension = file.extension;
      if (extension == null ||
          !['jpg', 'jpeg', 'png', 'webp'].contains(extension)) {
        showDesktopToast(
          context,
          l10n.profileAvatarFormatError,
          kind: DesktopToastKind.error,
        );
        return;
      }
      setState(() => _avatarBusy = true);
      final bytes = await file.readBytes();
      if (!mounted) return;
      if (bytes.isEmpty ||
          bytes.length > FileSizeThresholds.desktopAvatarUploadMaxBytes) {
        showDesktopToast(
          context,
          l10n.desktopProfileAvatarSizeError,
          kind: DesktopToastKind.error,
        );
        return;
      }
      await ref
          .read(profileCommandServiceProvider)
          .uploadAvatar(bytes, file.name);
      if (!mounted) return;
      await ref.read(authSessionProvider.notifier).reloadProfile();
      if (!mounted) return;
      showDesktopToast(
        context,
        l10n.profileAvatarSuccess,
        icon: DesktopIcons.check,
      );
    } on Object catch (error) {
      if (mounted) {
        showDesktopToast(
          context,
          failureToast(l10n, l10n.profileAvatarFailed, error),
          kind: DesktopToastKind.error,
          icon: DesktopIcons.info,
        );
      }
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  Future<void> _removeAvatar() async {
    if (_avatarBusy) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _avatarBusy = true);
    try {
      await ref.read(profileCommandServiceProvider).removeAvatar();
      if (!mounted) return;
      await ref.read(authSessionProvider.notifier).reloadProfile();
      if (!mounted) return;
      showDesktopToast(
        context,
        l10n.profileAvatarRemoved,
        icon: DesktopIcons.trash,
      );
    } on Object catch (error) {
      if (mounted) {
        showDesktopToast(
          context,
          failureToast(l10n, l10n.profileRemoveAvatar, error),
          kind: DesktopToastKind.error,
          icon: DesktopIcons.info,
        );
      }
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }
}

class _KvRow extends StatelessWidget {
  const _KvRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 160,
            child: Text(label, style: DesktopType.dense(skin.text3)),
          ),
          Expanded(
            child: Text(value, style: DesktopType.denseStrong(skin.text)),
          ),
        ],
      ),
    );
  }
}

class _StorageSection extends ConsumerWidget {
  const _StorageSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final stats = ref.watch(fileStorageStatsProvider).asData?.value;
    final used = stats == null ? '—' : formatFileSize(stats.usedBytes);
    final unlimited = stats?.isQuotaUnlimited ?? true;
    final total =
        stats == null || unlimited ? null : formatFileSize(stats.quotaBytes);
    final ratio = stats == null || unlimited ? 0.0 : stats.usageRatio;
    return _Card(
      title: l10n.desktopStorage,
      subtitle:
          unlimited
              ? l10n.desktopStorageUnlimited(used)
              : l10n.desktopStorageUsage(used, total!),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(used, style: DesktopType.bigNum(skin.text)),
              const SizedBox(width: 8),
              Text(
                unlimited ? '' : '· $total',
                style: DesktopType.dense(skin.text3),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            height: 8,
            decoration: BoxDecoration(
              color: skin.raise3,
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: ratio.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  color: skin.accent,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            stats == null
                ? '—'
                : stats.quotaBytes <= 0
                ? l10n.desktopStorageUnlimited(used)
                : '${(ratio * 100).round()}%',
            style: DesktopType.caption(skin.text3),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: skin.panel,
        borderRadius: BorderRadius.circular(DesktopMetrics.radiusCard),
        border: Border.all(color: skin.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: DesktopType.panelTitle(skin.text)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(subtitle!, style: DesktopType.caption(skin.text3)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}
