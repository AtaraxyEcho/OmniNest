import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/utils/color_value.dart';
import 'package:omninest/core/widgets/workstation_controls.dart';
import 'package:omninest/features/notifications/domain/notification_preferences.dart';
import 'package:omninest/features/notifications/domain/notification_type.dart';
import 'package:omninest/features/notifications/notification_ui.dart';
import 'package:omninest/features/tasks/application/task_notification_service.dart';

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
    final scheme = Theme.of(context).colorScheme;
    return _ProfilePreferenceCard(
      title: l10n.profileWeatherCity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.profileWeatherCityHint,
            style: TextStyle(
              fontSize: AppTypography.labelSmall,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          if (_editing)
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 32,
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      style: const TextStyle(
                        fontSize: AppTypography.bodyMedium,
                      ),
                      decoration: workstationInputDecoration(
                        context,
                        hintText: l10n.profileWeatherCityPlaceholder,
                        prefixIcon: Icons.location_city_outlined,
                      ),
                      onSubmitted: (_) => _submit(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                WorkstationIconButton(
                  tooltip: l10n.profileWeatherCitySave,
                  icon: Icons.check_rounded,
                  onPressed: _submit,
                ),
              ],
            )
          else
            _ValueRow(
              value: widget.city ?? l10n.profileWeatherCityNotSet,
              onPressed: () => setState(() => _editing = true),
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
    return _ProfilePreferenceCard(
      title: l10n.profileNotificationSettings,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PreferenceSwitchTile(
            icon: Icons.notifications_active_outlined,
            title: l10n.profileNotificationMasterSwitch,
            subtitle: l10n.profileNotificationMasterSwitchHint,
            value: widget.prefs.enabled,
            onChanged:
                (value) =>
                    widget.onChanged(widget.prefs.copyWith(enabled: value)),
          ),
          const _PreferenceDivider(),
          Consumer(
            builder: (context, ref, _) {
              final taskNotifyAsync = ref.watch(
                taskNotificationEnabledProvider,
              );
              return taskNotifyAsync.when(
                data:
                    (enabled) => _PreferenceSwitchTile(
                      icon: Icons.system_update_outlined,
                      title: l10n.profileTaskSystemNotifications,
                      subtitle: l10n.profileTaskSystemNotificationsHint,
                      value: enabled,
                      onChanged:
                          (value) => ref
                              .read(taskNotificationEnabledProvider.notifier)
                              .setEnabled(value),
                    ),
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
              );
            },
          ),
          const _PreferenceDivider(),
          widget.typesAsync.when(
            loading:
                () => const SizedBox(
                  height: 48,
                  child: Center(child: CircularProgressIndicator.adaptive()),
                ),
            error: (_, _) => Text(l10n.profileNotificationTypesLoadFailed),
            data: (types) => _buildTypes(context, types),
          ),
          const _PreferenceDivider(),
          _PreferenceSwitchTile(
            icon: Icons.volume_up_outlined,
            title: l10n.profileNotificationSound,
            subtitle: l10n.profileNotificationSoundHint,
            value: widget.prefs.sound,
            onChanged:
                (value) =>
                    widget.onChanged(widget.prefs.copyWith(sound: value)),
          ),
          const _PreferenceDivider(),
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
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _typesExpanded = !_typesExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.category_outlined,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.profileNotificationTypes(types.length),
                      style: TextStyle(
                        fontSize: AppTypography.bodyMedium,
                        fontWeight: FontWeight.w500,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _typesExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: Icon(
                      Icons.expand_more_rounded,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_typesExpanded)
          for (final type in types) ...[
            _PreferenceSwitchTile(
              icon: _iconFromString(type.icon),
              title: notificationTypeLabel(type.typeCode, l10n),
              subtitle:
                  notificationTypeDescription(type.typeCode, l10n) ??
                  type.description,
              value: widget.prefs.isTypeEnabled(type.typeCode),
              iconColor: _parseColor(type.color, context),
              onChanged:
                  widget.prefs.enabled
                      ? (value) {
                        final enabledTypes = Map<String, bool>.from(
                          widget.prefs.types,
                        );
                        enabledTypes[type.typeCode] = value;
                        widget.onChanged(
                          widget.prefs.copyWith(types: enabledTypes),
                        );
                      }
                      : null,
            ),
            const _PreferenceDivider(),
          ],
      ],
    );
  }

  Color _parseColor(String? hex, BuildContext context) {
    return parseHexColor(hex, Theme.of(context).colorScheme.onSurfaceVariant);
  }

  IconData _iconFromString(String? name) {
    return switch (name) {
      'check_circle_rounded' => Icons.check_circle_outlined,
      'error_rounded' => Icons.error_outline_rounded,
      'share_rounded' => Icons.share_outlined,
      'info_rounded' => Icons.info_outline_rounded,
      _ => Icons.notifications_outlined,
    };
  }
}

/// 偏好分区卡：个人中心工位分区卡的窄标题形态。
class _ProfilePreferenceCard extends StatelessWidget {
  const _ProfilePreferenceCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Text(
              title,
              style: TextStyle(
                fontSize: AppTypography.bodyMedium,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
          ),
          Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
          Padding(padding: const EdgeInsets.all(20), child: child),
        ],
      ),
    );
  }
}

/// 只读值行：细线框 + 值 + 编辑入口。
class _ValueRow extends StatelessWidget {
  const _ValueRow({required this.value, required this.onPressed});

  final String value;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest,
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(
                Icons.location_city_outlined,
                size: 14,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppTypography.bodyMedium,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              Icon(
                Icons.edit_outlined,
                size: 13,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreferenceDivider extends StatelessWidget {
  const _PreferenceDivider();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Divider(height: 1, thickness: 1, color: scheme.outlineVariant);
  }
}

/// 纯平偏好开关行：图标 + 标题/副文 + 右侧开关，行间以 1px 细线分隔。
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
    final scheme = Theme.of(context).colorScheme;
    final effectiveColor = iconColor ?? scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 16, color: effectiveColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: AppTypography.bodyMedium,
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurface,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: AppTypography.labelSmall,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          WorkstationSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
