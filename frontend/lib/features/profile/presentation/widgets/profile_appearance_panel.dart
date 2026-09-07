import 'package:flutter/material.dart';
import 'package:omninest/app/appearance/application/font_scale_controller.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/global_theme_colors.dart';
import 'package:omninest/core/widgets/workbench_panel.dart';

class ProfileAppearancePanel extends StatelessWidget {
  const ProfileAppearancePanel({
    required this.themeMode,
    required this.languageCode,
    required this.fontScalePreset,
    required this.onThemeChanged,
    required this.onLanguageChanged,
    required this.onFontScaleChanged,
    required this.onBackdropSettings,
    super.key,
  });

  final ThemeMode themeMode;
  final String languageCode;
  final FontScalePreset fontScalePreset;
  final ValueChanged<ThemeMode> onThemeChanged;
  final ValueChanged<String> onLanguageChanged;
  final ValueChanged<FontScalePreset> onFontScaleChanged;
  final VoidCallback onBackdropSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return WorkbenchPanel(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.profileSectionAppearance,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 22),
          _ResponsivePreferenceRow(
            icon: Icons.contrast_rounded,
            title: l10n.settingsAppearance,
            control: SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: const Icon(Icons.brightness_auto_rounded),
                  label: Text(l10n.settingsThemeSystem),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: const Icon(Icons.light_mode_rounded),
                  label: Text(l10n.settingsThemeLight),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: const Icon(Icons.dark_mode_rounded),
                  label: Text(l10n.settingsThemeDark),
                ),
              ],
              selected: {themeMode},
              onSelectionChanged:
                  (selection) => onThemeChanged(selection.first),
            ),
          ),
          const Divider(height: 32),
          _ResponsivePreferenceRow(
            icon: Icons.format_size_rounded,
            title: l10n.fontScaleTitle,
            control: SegmentedButton<FontScalePreset>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: FontScalePreset.followSystem,
                  label: Text(l10n.fontScaleFollowSystem),
                ),
                ButtonSegment(
                  value: FontScalePreset.compact,
                  label: Text(l10n.fontScaleCompact),
                ),
                ButtonSegment(
                  value: FontScalePreset.standard,
                  label: Text(l10n.fontScaleStandard),
                ),
                ButtonSegment(
                  value: FontScalePreset.comfortable,
                  label: Text(l10n.fontScaleComfortable),
                ),
                ButtonSegment(
                  value: FontScalePreset.large,
                  label: Text(l10n.fontScaleLarge),
                ),
              ],
              selected: {fontScalePreset},
              onSelectionChanged:
                  (selection) => onFontScaleChanged(selection.first),
            ),
          ),
          const Divider(height: 32),
          _ResponsivePreferenceRow(
            icon: Icons.language_rounded,
            title: l10n.settingsLanguage,
            control: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: 'zh',
                  label: Text(l10n.settingsLanguageChinese),
                ),
                ButtonSegment(
                  value: 'en',
                  label: Text(l10n.settingsLanguageEnglish),
                ),
              ],
              selected: {languageCode},
              onSelectionChanged:
                  (selection) => onLanguageChanged(selection.first),
            ),
          ),
          const Divider(height: 32),
          Material(
            type: MaterialType.transparency,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.wallpaper_rounded),
              title: Text(l10n.portalLocalBackdropTitle),
              subtitle: Text(l10n.portalLocalBackdropSubtitle),
              trailing: OutlinedButton.icon(
                onPressed: onBackdropSettings,
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: Text(l10n.profileManageBackdrop),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResponsivePreferenceRow extends StatelessWidget {
  const _ResponsivePreferenceRow({
    required this.icon,
    required this.title,
    required this.control,
  });

  final IconData icon;
  final String title;
  final Widget control;

  @override
  Widget build(BuildContext context) {
    final colors = context.globalColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 690;
        final label = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: colors.onSurfaceVariant),
            const SizedBox(width: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
          ],
        );
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [label, const SizedBox(height: 14), control],
          );
        }
        return Row(children: [label, const Spacer(), control]);
      },
    );
  }
}
