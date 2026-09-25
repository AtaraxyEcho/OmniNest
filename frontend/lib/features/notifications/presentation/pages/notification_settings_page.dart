import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/global_theme_colors.dart';
import 'package:omninest/core/utils/color_value.dart';
import 'package:omninest/core/widgets/workbench_panel.dart';
import 'package:omninest/features/notifications/application/notification_preferences_controller.dart';
import 'package:omninest/features/notifications/application/notification_type_controller.dart';
import 'package:omninest/features/notifications/domain/notification_preferences.dart';
import 'package:omninest/features/notifications/domain/notification_type.dart';
import 'package:omninest/features/notifications/presentation/utils/notification_type_l10n.dart';

/// 通知设置页面。
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
    final colors = context.globalColors;
    final typesAsync = ref.watch(notificationTypesProvider);
    final prefsAsync = ref.watch(notificationPreferencesProvider);

    return Scaffold(
      backgroundColor: colors.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: colors.surface.withValues(alpha: 0.86),
        leading: IconButton(
          tooltip: l10n.coreBack,
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/profile'),
        ),
        title: Text(
          l10n.profileNotificationSettings,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: prefsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(l10n.filesLoadFailed('$e'))),
        data: (prefs) {
          _prefs ??= prefs;
          return _buildBody(typesAsync, colors);
        },
      ),
    );
  }

  Widget _buildBody(
    AsyncValue<List<NotificationTypeConfig>> typesAsync,
    GlobalThemeColors colors,
  ) {
    final l10n = AppLocalizations.of(context);
    final prefs = _prefs!;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          _Section(
            colors: colors,
            child: _SwitchTile(
              icon: Icons.notifications_active_outlined,
              title: l10n.profileNotificationMasterSwitch,
              subtitle: l10n.profileNotificationMasterSwitchHint,
              value: prefs.enabled,
              colors: colors,
              onChanged: (v) => _updatePrefs(prefs.copyWith(enabled: v)),
            ),
          ),
          const SizedBox(height: 12),
          _Section(
            colors: colors,
            child: typesAsync.when(
              loading:
                  () => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              error:
                  (_, _) => Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      l10n.profileNotificationTypesLoadFailed,
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ),
              data:
                  (types) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                        child: Row(
                          children: [
                            Icon(
                              Icons.category_outlined,
                              size: 18,
                              color: colors.primary,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              l10n.notificationTypesHeader,
                              style: TextStyle(
                                fontSize: AppTypography.titleMedium,
                                fontWeight: FontWeight.w700,
                                color: colors.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ...types.map(
                        (type) => _buildTypeTile(type, prefs, colors, l10n),
                      ),
                    ],
                  ),
            ),
          ),
          const SizedBox(height: 12),
          _Section(
            colors: colors,
            child: Column(
              children: [
                _SwitchTile(
                  icon: Icons.volume_up_outlined,
                  title: l10n.profileNotificationSound,
                  subtitle: l10n.profileNotificationSoundHint,
                  value: prefs.sound,
                  colors: colors,
                  onChanged: (v) => _updatePrefs(prefs.copyWith(sound: v)),
                ),
                Divider(
                  height: 1,
                  indent: 68,
                  color: colors.outlineVariant.withValues(alpha: 0.12),
                ),
                _SwitchTile(
                  icon: Icons.preview_outlined,
                  title: l10n.profileNotificationPreview,
                  subtitle: l10n.profileNotificationPreviewHint,
                  value: prefs.showPreview,
                  colors: colors,
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

  Widget _buildTypeTile(
    NotificationTypeConfig type,
    NotificationPreferences prefs,
    GlobalThemeColors colors,
    AppLocalizations l10n,
  ) {
    final isTypeEnabled = prefs.isTypeEnabled(type.typeCode);
    final color = _parseColor(type.color, colors);
    return _SwitchTile(
      icon: _iconFromString(type.icon),
      title: notificationTypeLabel(type.typeCode, l10n),
      subtitle:
          notificationTypeDescription(type.typeCode, l10n) ?? type.description,
      value: isTypeEnabled,
      colors: colors,
      iconColor: color,
      onChanged:
          prefs.enabled
              ? (v) {
                final newTypes = Map<String, bool>.from(prefs.types);
                newTypes[type.typeCode] = v;
                _updatePrefs(prefs.copyWith(types: newTypes));
              }
              : null,
    );
  }

  Future<void> _updatePrefs(NotificationPreferences newPrefs) async {
    setState(() => _prefs = newPrefs);
    await ref.read(notificationPreferencesProvider.notifier).save(newPrefs);
  }

  Color _parseColor(String? hex, GlobalThemeColors colors) {
    return parseHexColor(hex, colors.onSurfaceVariant);
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

// ─── Section ────────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  const _Section({required this.child, required this.colors});

  final Widget child;
  final GlobalThemeColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: WorkbenchPanel(padding: EdgeInsets.zero, child: child),
    );
  }
}

// ─── Switch Tile ────────────────────────────────────────────────────────────

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    this.onChanged,
    this.iconColor,
    required this.colors,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? iconColor;
  final GlobalThemeColors colors;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = iconColor ?? colors.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: effectiveColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
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
                      color: colors.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: colors.primary,
          ),
        ],
      ),
    );
  }
}
