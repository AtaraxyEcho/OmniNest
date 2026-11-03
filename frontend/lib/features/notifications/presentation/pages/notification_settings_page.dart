import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/feedback/omni_feedback.dart';
import 'package:omninest/core/theme/workstation_scope.dart';
import 'package:omninest/core/utils/color_value.dart';
import 'package:omninest/core/widgets/workstation_controls.dart';
import 'package:omninest/core/widgets/workstation_dialog.dart';
import 'package:omninest/core/widgets/workstation_portal_link.dart';
import 'package:omninest/features/notifications/application/notification_preferences_controller.dart';
import 'package:omninest/features/notifications/application/notification_type_controller.dart';
import 'package:omninest/features/notifications/domain/notification_preferences.dart';
import 'package:omninest/features/notifications/domain/notification_type.dart';
import 'package:omninest/features/notifications/presentation/utils/notification_type_l10n.dart';
import 'package:omninest/features/notifications/presentation/widgets/notification_quiet_hours_fields.dart';

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
  String? _updatingTypeId;
  bool _sendingTestEmail = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final typesAsync = ref.watch(notificationTypesProvider);
    final prefsAsync = ref.watch(notificationPreferencesProvider);
    final permissions =
        ref.watch(authSessionProvider).value?.user?.permissions ??
        const <String>{};
    final canReadConfig = permissions.contains('system:config:read');
    final canManageConfig = permissions.contains('system:config:manage');

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
                        (_, _) => Center(
                          child: Text(
                            l10n.notificationLoadFailed,
                            textAlign: TextAlign.center,
                          ),
                        ),
                    data:
                        (prefs) => _buildBody(
                          context,
                          typesAsync,
                          prefs,
                          canReadConfig: canReadConfig,
                          canManageConfig: canManageConfig,
                        ),
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
    NotificationPreferences prefs, {
    required bool canReadConfig,
    required bool canManageConfig,
  }) {
    final l10n = AppLocalizations.of(context);
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
              onChanged:
                  (v) => unawaited(_updatePrefs(prefs.copyWith(enabled: v))),
            ),
          ),
          if (canManageConfig) ...[
            const SizedBox(height: 12),
            _buildEmailTestSection(context, l10n),
          ],
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
                                  unawaited(
                                    _updatePrefs(
                                      prefs.copyWith(types: newTypes),
                                    ),
                                  );
                                }
                                : null,
                      ),
                  ],
                );
              },
            ),
          ),
          if (canReadConfig) ...[
            const SizedBox(height: 12),
            _buildTypeAdminSection(context, l10n, canManage: canManageConfig),
          ],
          const SizedBox(height: 12),
          _SettingsSection(
            child: Column(
              children: [
                _SettingsSwitchRow(
                  icon: Icons.volume_up_outlined,
                  title: l10n.profileNotificationSound,
                  subtitle: l10n.profileNotificationSoundHint,
                  value: prefs.sound,
                  onChanged:
                      (v) => unawaited(_updatePrefs(prefs.copyWith(sound: v))),
                ),
                _SettingsDivider(),
                _SettingsSwitchRow(
                  icon: Icons.preview_outlined,
                  title: l10n.profileNotificationPreview,
                  subtitle: l10n.profileNotificationPreviewHint,
                  value: prefs.showPreview,
                  onChanged:
                      (v) => unawaited(
                        _updatePrefs(prefs.copyWith(showPreview: v)),
                      ),
                ),
                _SettingsDivider(),
                _SettingsSwitchRow(
                  icon: Icons.campaign_outlined,
                  title: l10n.notificationForegroundToastToggle,
                  subtitle: l10n.notificationForegroundToastToggleSubtitle,
                  value: prefs.foregroundBanner,
                  onChanged:
                      (v) => unawaited(
                        _updatePrefs(prefs.copyWith(foregroundBanner: v)),
                      ),
                ),
                _SettingsDivider(),
                _SettingsSwitchRow(
                  icon: Icons.mail_outline_rounded,
                  title: l10n.profileNotificationEmail,
                  subtitle: l10n.profileNotificationEmailHint,
                  value: prefs.emailNotification,
                  onChanged:
                      (v) => unawaited(
                        _updatePrefs(prefs.copyWith(emailNotification: v)),
                      ),
                ),
                _SettingsDivider(),
                _SettingsSwitchRow(
                  icon: Icons.nightlight_outlined,
                  title: l10n.notificationQuietHours,
                  subtitle: l10n.notificationQuietHoursHint,
                  value: prefs.quietHours.enabled,
                  onChanged:
                      (v) => unawaited(
                        _updatePrefs(
                          prefs.copyWith(
                            quietHours: prefs.quietHours.copyWith(enabled: v),
                          ),
                        ),
                      ),
                ),
                NotificationQuietHoursFields(
                  start: prefs.quietHours.start,
                  end: prefs.quietHours.end,
                  enabled: prefs.quietHours.enabled,
                  onChanged:
                      (start, end) => unawaited(
                        _updatePrefs(
                          prefs.copyWith(
                            quietHours: prefs.quietHours.copyWith(
                              start: start,
                              end: end,
                            ),
                          ),
                        ),
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailTestSection(BuildContext context, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    return _SettingsSection(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.mark_email_read_outlined,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.notificationEmailTestTitle,
                    style: TextStyle(
                      fontSize: AppTypography.bodyMedium,
                      fontWeight: FontWeight.w500,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              l10n.notificationEmailTestSubtitle,
              style: TextStyle(
                fontSize: AppTypography.labelSmall,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _sendingTestEmail ? null : _sendTestEmail,
              icon: const Icon(Icons.send_outlined, size: 18),
              label: Text(l10n.notificationEmailTestAction),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendTestEmail() async {
    final l10n = AppLocalizations.of(context);
    final input = await showWorkstationDialog<({String to})>(
      context: context,
      dismissible: false,
      builder: (_) => const _EmailTestDialog(),
    );
    if (input == null || !mounted) {
      return;
    }
    setState(() => _sendingTestEmail = true);
    try {
      await ref
          .read(notificationAdminActionsProvider)
          .sendTestEmail(to: input.to);
      if (!mounted) {
        return;
      }
      showOmniFeedback(
        context,
        l10n.notificationEmailTestSent,
        severity: OmniFeedbackSeverity.success,
      );
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      showOmniFeedback(
        context,
        describeUserFacingError(error, l10n: l10n).displayMessage,
        severity: OmniFeedbackSeverity.error,
      );
    } finally {
      if (mounted) {
        setState(() => _sendingTestEmail = false);
      }
    }
  }

  Widget _buildTypeAdminSection(
    BuildContext context,
    AppLocalizations l10n, {
    required bool canManage,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final typesAsync = ref.watch(allNotificationTypesProvider);
    return _SettingsSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 2),
            child: Text(
              l10n.notificationTypeAdminTitle,
              style: TextStyle(
                fontSize: AppTypography.bodyMedium,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              l10n.notificationTypeAdminSubtitle,
              style: TextStyle(
                fontSize: AppTypography.labelSmall,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          typesAsync.when(
            loading: () => const _NotificationAdminSkeleton(),
            error:
                (error, _) => Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          describeUserFacingError(
                            error,
                            l10n: l10n,
                          ).displayMessage,
                          style: TextStyle(
                            fontSize: AppTypography.labelSmall,
                            color: scheme.error,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed:
                            () => ref.invalidate(allNotificationTypesProvider),
                        child: Text(l10n.commonRetry),
                      ),
                    ],
                  ),
                ),
            data: (types) {
              if (types.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Text(
                    l10n.notificationTypeAdminEmpty,
                    style: TextStyle(
                      fontSize: AppTypography.labelSmall,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                );
              }
              return Column(
                children: [
                  for (final type in types)
                    _SettingsSwitchRow(
                      icon: _iconFromString(type.icon),
                      title: notificationTypeLabel(type.typeCode, l10n),
                      subtitle:
                          notificationTypeDescription(type.typeCode, l10n) ??
                          type.description,
                      value: type.enabled,
                      iconColor: _parseColor(type.color, context),
                      onChanged:
                          canManage &&
                                  type.id != null &&
                                  _updatingTypeId == null
                              ? (value) => unawaited(_toggleType(type, value))
                              : null,
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _toggleType(NotificationTypeConfig type, bool enabled) async {
    final id = type.id;
    if (id == null) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final label = notificationTypeLabel(type.typeCode, l10n);
    final confirmed = await _confirmTypeToggle(
      context,
      label: label,
      enabled: enabled,
    );
    if (!confirmed || !mounted) {
      return;
    }
    setState(() => _updatingTypeId = id);
    try {
      await ref
          .read(notificationAdminActionsProvider)
          .setTypeEnabled(id, enabled: enabled);
      if (!mounted) {
        return;
      }
      showOmniFeedback(
        context,
        l10n.notificationTypeAdminUpdated,
        severity: OmniFeedbackSeverity.success,
      );
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      showOmniFeedback(
        context,
        describeUserFacingError(error, l10n: l10n).displayMessage,
        severity: OmniFeedbackSeverity.error,
      );
    } finally {
      if (mounted) {
        setState(() => _updatingTypeId = null);
      }
    }
  }

  Future<bool> _confirmTypeToggle(
    BuildContext context, {
    required String label,
    required bool enabled,
  }) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showWorkstationDialog<bool>(
      context: context,
      dismissible: false,
      builder:
          (dialogContext) => WorkstationDialogFrame(
            title: l10n.notificationTypeAdminTitle,
            body: Text(
              l10n.notificationTypeAdminToggleConfirm(
                label,
                enabled
                    ? l10n.notificationTypeAdminStateEnabled
                    : l10n.notificationTypeAdminStateDisabled,
              ),
              style: Theme.of(dialogContext).textTheme.bodyMedium,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(l10n.coreCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(l10n.notificationTypeAdminConfirm),
              ),
            ],
          ),
    );
    return confirmed == true;
  }

  /// 偏好控制器在 save 失败时已把 state 回滚，页面不再自持副本；
  /// 这里只补失败反馈，并在回写前确认页面仍在挂载。
  Future<void> _updatePrefs(NotificationPreferences newPrefs) async {
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(notificationPreferencesProvider.notifier).save(newPrefs);
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      showOmniFeedback(
        context,
        failureToast(l10n, l10n.profileNotificationSaveFailed, error),
        severity: OmniFeedbackSeverity.error,
      );
    }
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

/// 管理列表的静态加载占位：页面已有偏好与类型两处转圈，这里不再叠加动画。
class _NotificationAdminSkeleton extends StatelessWidget {
  const _NotificationAdminSkeleton();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        children: [
          for (var index = 0; index < 3; index++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Container(
                height: 12,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
        ],
      ),
    );
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

/// 测试邮件收件人：留空由服务端发给当前管理员邮箱。
class _EmailTestDialog extends StatefulWidget {
  const _EmailTestDialog();

  @override
  State<_EmailTestDialog> createState() => _EmailTestDialogState();
}

class _EmailTestDialogState extends State<_EmailTestDialog> {
  final TextEditingController _recipient = TextEditingController();

  @override
  void dispose() {
    _recipient.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return WorkstationDialogFrame(
      title: l10n.notificationEmailTestTitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.notificationEmailTestConfirm,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _recipient,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: l10n.notificationEmailTestRecipient,
              hintText: l10n.notificationEmailTestRecipientHint,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.coreCancel),
        ),
        FilledButton(
          onPressed:
              () => Navigator.of(context).pop((to: _recipient.text.trim())),
          child: Text(l10n.notificationEmailTestAction),
        ),
      ],
    );
  }
}
