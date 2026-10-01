import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/theme/workstation_scope.dart';
import 'package:omninest/core/utils/color_value.dart';
import 'package:omninest/core/widgets/workstation_controls.dart';
import 'package:omninest/core/widgets/workstation_portal_link.dart';
import 'package:omninest/features/notifications/application/notification_preferences_controller.dart';
import 'package:omninest/features/notifications/application/notification_type_controller.dart';
import 'package:omninest/features/notifications/domain/notification_preferences.dart';
import 'package:omninest/features/notifications/domain/notification_type.dart';
import 'package:omninest/features/notifications/presentation/utils/notification_type_l10n.dart';

/// 通知偏好设置页：56px 工位顶栏 + 分区卡开关行。
///
/// 桌面从个人中心通知分区进入，移动端经 `/profile/notifications` 直达；
/// 本页只承载偏好开关，与桌面分区卡共享同一套语义。
class NotificationSettingsPage extends ConsumerStatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  ConsumerState<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState
    extends ConsumerState<NotificationSettingsPage> {
  NotificationPreferences? _prefs;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final typesAsync = ref.watch(notificationTypesProvider);
    final prefsAsync = ref.watch(notificationPreferencesProvider);

    return WorkstationScope(
      child: Builder(
        builder: (context) {
          final scheme = Theme.of(context).colorScheme;
          return Scaffold(
            backgroundColor: scheme.surface,
            body: Column(
              children: [
                _SettingsTopBar(title: l10n.profileNotificationSettings),
                Expanded(
                  child: prefsAsync.when(
                    loading:
                        () => const Center(
                          child: CircularProgressIndicator.adaptive(),
                        ),
                    error:
                        (e, _) =>
                            Center(child: Text(l10n.filesLoadFailed('$e'))),
                    data: (prefs) {
                      _prefs ??= prefs;
                      return _buildBody(context, typesAsync);
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AsyncValue<List<NotificationTypeConfig>> typesAsync,
  ) {
    final l10n = AppLocalizations.of(context);
    final prefs = _prefs!;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SettingsSection(
            child: _SettingsSwitchRow(
              icon: Icons.notifications_active_outlined,
              title: l10n.profileNotificationMasterSwitch,
              subtitle: l10n.profileNotificationMasterSwitchHint,
              value: prefs.enabled,
              onChanged: (v) => _updatePrefs(prefs.copyWith(enabled: v)),
            ),
          ),
          const SizedBox(height: 12),
          _SettingsSection(
            child: typesAsync.when(
              loading:
                  () => const SizedBox(
                    height: 64,
                    child: Center(child: CircularProgressIndicator.adaptive()),
                  ),
              error:
                  (_, _) => Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(l10n.profileNotificationTypesLoadFailed),
                  ),
              data: (types) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                      child: Text(
                        l10n.notificationTypesHeader,
                        style: TextStyle(
                          fontSize: AppTypography.bodyMedium,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    for (final type in types)
                      _SettingsSwitchRow(
                        icon: _iconFromString(type.icon),
                        title: notificationTypeLabel(type.typeCode, l10n),
                        subtitle:
                            notificationTypeDescription(type.typeCode, l10n) ??
                            type.description,
                        value: prefs.isTypeEnabled(type.typeCode),
                        iconColor: _parseColor(type.color, context),
                        onChanged:
                            prefs.enabled
                                ? (v) {
                                  final newTypes = Map<String, bool>.from(
                                    prefs.types,
                                  );
                                  newTypes[type.typeCode] = v;
                                  _updatePrefs(prefs.copyWith(types: newTypes));
                                }
                                : null,
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          _SettingsSection(
            child: Column(
              children: [
                _SettingsSwitchRow(
                  icon: Icons.volume_up_outlined,
                  title: l10n.profileNotificationSound,
                  subtitle: l10n.profileNotificationSoundHint,
                  value: prefs.sound,
                  onChanged: (v) => _updatePrefs(prefs.copyWith(sound: v)),
                ),
                _SettingsDivider(),
                _SettingsSwitchRow(
                  icon: Icons.preview_outlined,
                  title: l10n.profileNotificationPreview,
                  subtitle: l10n.profileNotificationPreviewHint,
                  value: prefs.showPreview,
                  onChanged:
                      (v) => _updatePrefs(prefs.copyWith(showPreview: v)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _updatePrefs(NotificationPreferences newPrefs) async {
    setState(() => _prefs = newPrefs);
    await ref.read(notificationPreferencesProvider.notifier).save(newPrefs);
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

class _SettingsTopBar extends StatelessWidget {
  const _SettingsTopBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const WorkstationPortalLink(),
          const SizedBox(width: 12),
          SizedBox(
            height: 16,
            child: VerticalDivider(width: 1, color: scheme.outlineVariant),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppTypography.bodyMedium,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 分区卡：0px 直角 + 1px 细线。
class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: child,
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Divider(height: 1, thickness: 1, color: scheme.outlineVariant);
  }
}

/// 纯平开关行：图标 + 标题/副文 + 右侧开关。
class _SettingsSwitchRow extends StatelessWidget {
  const _SettingsSwitchRow({
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
