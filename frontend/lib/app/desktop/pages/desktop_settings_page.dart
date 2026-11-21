import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omninest/app/appearance/application/appearance_controller.dart';
import 'package:omninest/app/appearance/application/font_scale_controller.dart';
import 'package:omninest/app/desktop/desktop_backdrop_scope.dart';
import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_shell_state.dart';
import 'package:omninest/app/desktop/desktop_toast.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_dialogs.dart';
import 'package:omninest/app/desktop/widgets/desktop_error_view.dart';
import 'package:omninest/app/desktop/widgets/desktop_fields.dart';
import 'package:omninest/app/desktop/widgets/desktop_focus_outline.dart';
import 'package:omninest/app/desktop/widgets/desktop_glass.dart';
import 'package:omninest/app/desktop/widgets/desktop_surfaces.dart';
import 'package:omninest/app/desktop/widgets/desktop_skeleton.dart';
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
import 'package:omninest/features/profile/presentation/widgets/profile_two_factor_card.dart';
import 'package:omninest/features/music/application/music_scan_job_controller.dart';
import 'package:omninest/features/music/music_portal.dart';
import 'package:omninest/features/music/presentation/widgets/music_platform_login.dart'
    show PlatformLoginSheet;
import 'package:omninest/features/portal/portal_weather.dart';
import 'package:omninest/features/portal/application/weather_provider.dart'
    show weatherApiProvider;
import 'package:omninest/features/portal/data/weather_api.dart'
    show WeatherCitySuggestion;
import 'package:omninest/platform/file_pick.dart';

part 'desktop_settings_backdrop.dart';
part 'desktop_settings_backdrop_library.dart';
part 'desktop_settings_more.dart';
part 'desktop_settings_weather.dart';
part 'desktop_settings_storage.dart';
part 'desktop_settings_controls.dart';
part 'desktop_settings_sections.dart';

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
  static DesktopSettingsSection _parseSection(String? raw) => switch (raw) {
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

  late DesktopSettingsSection _section = _parseSection(widget.initialSection);

  @override
  void didUpdateWidget(covariant DesktopSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSection != widget.initialSection &&
        widget.initialSection != null) {
      final next = _parseSection(widget.initialSection);
      if (next != _section) {
        setState(() => _section = next);
      }
    }
  }

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
            // 样例 `Settings.tsx:39` 的 PageHead 只有眉标 + 标题，没有副标题。
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 980;
              final nav = SizedBox(
                width: narrow ? double.infinity : 220,
                child: Wrap(
                  direction: narrow ? Axis.horizontal : Axis.vertical,
                  spacing: narrow ? 6 : 0,
                  runSpacing: narrow ? 6 : 0,
                  children: [
                    for (final section in DesktopSettingsSection.values)
                      SizedBox(
                        width: narrow ? null : 220,
                        child: _NavRow(
                          label: labels[section] ?? '',
                          icon: icons[section]!,
                          active: _section == section,
                          onTap: () => setState(() => _section = section),
                        ),
                      ),
                  ],
                ),
              );
              final body = LayoutBuilder(
                builder: (context, bodyConstraints) {
                  final bodyWidth =
                      bodyConstraints.maxWidth > 760
                          ? 760.0
                          : bodyConstraints.maxWidth;
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
                          DesktopSettingsSection.about => const _AboutSection(),
                        },
                      ),
                    ),
                  );
                },
              );
              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [nav, const SizedBox(height: 16), body],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  nav,
                  const SizedBox(width: 40),
                  Expanded(child: body),
                ],
              );
            },
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
      child: DesktopFocusOutline(
        radius: DesktopMetrics.radiusButton,
        onActivate: onTap,
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
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: DesktopFocusOutline(
        radius: 16,
        onActivate: onTap,
        child: DesktopHover(
          builder:
              (context, hovered) => GestureDetector(
                onTap: onTap,
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: DesktopMotion.of(context, DesktopMotion.fast),
                  transform: Matrix4.translationValues(0, hovered ? -3 : 0, 0),
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                  decoration: BoxDecoration(
                    color: selected ? skin.raise2 : skin.raise,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: selected ? skin.accent : skin.line,
                      width: selected ? DesktopMetrics.hairlineStrong : 1,
                    ),
                    boxShadow:
                        selected
                            ? [
                              BoxShadow(
                                color: skin.accentWash(0.16),
                                blurRadius: 0,
                                spreadRadius: 4,
                              ),
                            ]
                            : null,
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _ThemePreview(
                            background: preview,
                            line: line,
                            accent: skin.accent,
                            dark: dark,
                            system: mode == ThemeMode.system,
                          ),
                          const SizedBox(height: 10),
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Text(
                              label,
                              style: DesktopType.bodyStrong(skin.text),
                            ),
                          ),
                        ],
                      ),
                      if (selected)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: skin.accent,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              DesktopIcons.check,
                              size: 12,
                              color: skin.accentInk,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
        ),
      ),
    );
  }
}

class _ThemePreview extends StatelessWidget {
  const _ThemePreview({
    required this.background,
    required this.line,
    required this.accent,
    required this.dark,
    this.system = false,
  });

  final Color background;
  final Color line;
  final Color accent;
  final bool dark;
  final bool system;

  Widget _block(Color color) => DecoratedBox(
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(6),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final muted =
        system
            ? const Color(0xFF7B8580).withValues(alpha: 0.28)
            : line.withValues(alpha: dark ? 0.25 : 0.35);
    return SizedBox(
      height: 84,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          children: [
            if (system)
              const Positioned.fill(
                child: CustomPaint(
                  painter: _SystemThemeSplitPainter(
                    darkColor: Color(0xFF0D1114),
                    lightColor: Color(0xFFECEEE9),
                  ),
                ),
              )
            else
              Positioned.fill(child: ColoredBox(color: background)),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 22, child: _block(muted)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            height: 20,
                            child: _block(
                              accent.withValues(alpha: dark ? 0.52 : 0.35),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Expanded(child: _block(muted)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(width: 24, child: _block(muted)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SystemThemeSplitPainter extends CustomPainter {
  const _SystemThemeSplitPainter({
    required this.darkColor,
    required this.lightColor,
  });

  final Color darkColor;
  final Color lightColor;

  @override
  void paint(Canvas canvas, Size size) {
    final darkPaint = Paint()..color = darkColor;
    final lightPaint = Paint()..color = lightColor;
    canvas.drawRect(Offset.zero & size, darkPaint);
    final lightPath =
        Path()
          ..moveTo(size.width, 0)
          ..lineTo(size.width, size.height)
          ..lineTo(0, size.height)
          ..close();
    canvas.drawPath(lightPath, lightPaint);
  }

  @override
  bool shouldRepaint(_SystemThemeSplitPainter oldDelegate) =>
      oldDelegate.darkColor != darkColor ||
      oldDelegate.lightColor != lightColor;
}
