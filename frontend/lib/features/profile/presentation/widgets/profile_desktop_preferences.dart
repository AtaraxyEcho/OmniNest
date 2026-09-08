import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/global_theme_colors.dart';
import 'package:omninest/core/widgets/workbench_panel.dart';
import 'package:omninest/features/notifications/domain/notification_preferences.dart';
import 'package:omninest/features/notifications/domain/notification_type.dart';
import 'package:omninest/features/notifications/notification_ui.dart';

/// 桌面端个人中心的天气城市设置。
class ProfileWeatherCityCard extends StatefulWidget {
  const ProfileWeatherCityCard({
    required this.city,
    required this.onChanged,
    super.key,
  });

  final String? city;
  final ValueChanged<String> onChanged;

  @override
  State<ProfileWeatherCityCard> createState() => _ProfileWeatherCityCardState();
}

class _ProfileWeatherCityCardState extends State<ProfileWeatherCityCard> {
  late final TextEditingController _controller;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.city ?? '');
  }

  @override
  void didUpdateWidget(ProfileWeatherCityCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.city != widget.city && !_editing) {
      _controller.text = widget.city ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    widget.onChanged(_controller.text);
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.globalColors;
    return WorkbenchPanel(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PreferenceHeader(
            icon: Icons.cloud_outlined,
            title: l10n.profileWeatherCity,
          ),
          const SizedBox(height: 6),
          Text(
            l10n.profileWeatherCityHint,
            style: TextStyle(
              fontSize: AppTypography.bodySmall,
              color: colors.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 16),
          if (_editing)
            TextField(
              controller: _controller,
              autofocus: true,
              style: TextStyle(
                fontSize: AppTypography.bodyLarge,
                color: colors.onSurface,
              ),
              decoration: InputDecoration(
                hintText: l10n.profileWeatherCityPlaceholder,
                isDense: true,
                suffixIcon: IconButton(
                  onPressed: _submit,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  tooltip: l10n.profileWeatherCitySave,
                ),
              ),
              onSubmitted: (_) => _submit(),
            )
          else
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              tileColor: colors.surfaceContainerHighest.withValues(alpha: 0.4),
              leading: const Icon(Icons.location_city_rounded, size: 18),
              title: Text(
                widget.city ?? l10n.profileWeatherCityNotSet,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.edit_outlined, size: 16),
              onTap: () => setState(() => _editing = true),
            ),
        ],
      ),
    );
  }
}

/// 桌面端个人中心的通知偏好设置。
class ProfileNotificationSettingsCard extends StatefulWidget {
  const ProfileNotificationSettingsCard({
    required this.typesAsync,
    required this.prefs,
    required this.onChanged,
    super.key,
  });

  final AsyncValue<List<NotificationTypeConfig>> typesAsync;
  final NotificationPreferences prefs;
  final ValueChanged<NotificationPreferences> onChanged;

  @override
  State<ProfileNotificationSettingsCard> createState() =>
      _ProfileNotificationSettingsCardState();
}

class _ProfileNotificationSettingsCardState
    extends State<ProfileNotificationSettingsCard> {
  bool _typesExpanded = true;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return WorkbenchPanel(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PreferenceHeader(
            icon: Icons.notifications_outlined,
            title: l10n.profileNotificationSettings,
          ),
          const SizedBox(height: 16),
          _PreferenceSwitchTile(
            icon: Icons.notifications_active_outlined,
            title: l10n.profileNotificationMasterSwitch,
            subtitle: l10n.profileNotificationMasterSwitchHint,
            value: widget.prefs.enabled,
            onChanged:
                (value) =>
                    widget.onChanged(widget.prefs.copyWith(enabled: value)),
          ),
          const SizedBox(height: 12),
          widget.typesAsync.when(
            loading:
                () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator.adaptive()),
                ),
            error:
                (_, _) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(l10n.profileNotificationTypesLoadFailed),
                ),
            data: (types) => _buildTypes(context, types),
          ),
          const SizedBox(height: 12),
          _PreferenceSwitchTile(
            icon: Icons.volume_up_outlined,
            title: l10n.profileNotificationSound,
            subtitle: l10n.profileNotificationSoundHint,
            value: widget.prefs.sound,
            onChanged:
                (value) =>
                    widget.onChanged(widget.prefs.copyWith(sound: value)),
          ),
          const SizedBox(height: 12),
          _PreferenceSwitchTile(
            icon: Icons.preview_outlined,
            title: l10n.profileNotificationPreview,
            subtitle: l10n.profileNotificationPreviewHint,
            value: widget.prefs.showPreview,
            onChanged:
                (value) =>
                    widget.onChanged(widget.prefs.copyWith(showPreview: value)),
          ),
        ],
      ),
    );
  }

  Widget _buildTypes(BuildContext context, List<NotificationTypeConfig> types) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          leading: const Icon(Icons.category_outlined, size: 18),
          title: Text(l10n.profileNotificationTypes(types.length)),
          trailing: AnimatedRotation(
            turns: _typesExpanded ? 0.5 : 0,
            duration: const Duration(milliseconds: 190),
            child: const Icon(Icons.expand_more_rounded),
          ),
          onTap: () => setState(() => _typesExpanded = !_typesExpanded),
        ),
        if (_typesExpanded)
          for (final type in types) ...[
            const SizedBox(height: 10),
            _buildTypeTile(context, type),
          ],
      ],
    );
  }

  Widget _buildTypeTile(BuildContext context, NotificationTypeConfig type) {
    final l10n = AppLocalizations.of(context);
    final typeEnabled = widget.prefs.isTypeEnabled(type.typeCode);
    return _PreferenceSwitchTile(
      icon: _iconFromString(type.icon),
      title: notificationTypeLabel(type.typeCode, l10n),
      subtitle:
          notificationTypeDescription(type.typeCode, l10n) ?? type.description,
      value: typeEnabled,
      iconColor: _parseColor(type.color, context),
      onChanged:
          widget.prefs.enabled
              ? (value) {
                final enabledTypes = Map<String, bool>.from(widget.prefs.types);
                enabledTypes[type.typeCode] = value;
                widget.onChanged(widget.prefs.copyWith(types: enabledTypes));
              }
              : null,
    );
  }

  Color _parseColor(String? hex, BuildContext context) {
    if (hex == null || hex.isEmpty) {
      return context.globalColors.onSurfaceVariant;
    }
    final value = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
    return value == null
        ? context.globalColors.onSurfaceVariant
        : Color(0xFF000000 | value);
  }

  IconData _iconFromString(String? name) {
    return switch (name) {
      'check_circle_rounded' => Icons.check_circle_rounded,
      'error_rounded' => Icons.error_rounded,
      'share_rounded' => Icons.share_rounded,
      'info_rounded' => Icons.info_rounded,
      _ => Icons.notifications_outlined,
    };
  }
}

class _PreferenceHeader extends StatelessWidget {
  const _PreferenceHeader({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.globalColors;
    return Row(
      children: [
        Icon(icon, size: 18, color: colors.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: AppTypography.titleMedium,
              fontWeight: FontWeight.w700,
              color: colors.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}

class _PreferenceSwitchTile extends StatelessWidget {
  const _PreferenceSwitchTile({
    required this.icon,
    required this.title,
    required this.value,
    this.subtitle,
    this.onChanged,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.globalColors;
    final effectiveColor = iconColor ?? colors.onSurfaceVariant;
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: effectiveColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: effectiveColor),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: AppTypography.bodyLarge,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: AppTypography.bodySmall,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        Switch.adaptive(value: value, onChanged: onChanged),
      ],
    );
  }
}
