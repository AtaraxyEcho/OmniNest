part of 'desktop_settings_page.dart';

/// 通知类型级开关与免打扰时段编辑：独立成 part，避免设置页主文件过长。
/// 通知偏好：与服务端偏好同一份快照，改动立即回写（失败回滚）。
class _NotificationsSection extends ConsumerWidget {
  const _NotificationsSection();

  static const List<String> _knownTypeCodes = <String>[
    'TASK_COMPLETED',
    'TASK_FAILED',
    'SHARE_ACCESS',
    'SYSTEM_MESSAGE',
    'MEDIA_SCRAPED',
    'SHARE_ACCESSED',
    'QUOTA_WARNING',
    'NEW_DEVICE_LOGIN',
    'PASSWORD_CHANGED',
    'SECURITY_THREAT',
    'SECURITY_SCAN_FAILED',
    'MEDIA_AUTO_IMPORT_COMPLETED',
    'MEDIA_AUTO_IMPORT_FAILED',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final prefsAsync = ref.watch(notificationPreferencesProvider);
    final prefs = prefsAsync.asData?.value;
    if (prefs == null) {
      return _Card(
        title: l10n.settingsNotification,
        child: Text(
          prefsAsync.hasError ? l10n.notificationLoadFailed : '',
          style: DesktopType.dense(skin.text3),
        ),
      );
    }
    final controller = ref.read(notificationPreferencesProvider.notifier);
    Future<void> save(
      NotificationPreferences next, {
      String? successMessage,
    }) async {
      try {
        await controller.save(next);
        if (successMessage != null && context.mounted) {
          showDesktopToast(context, successMessage, icon: DesktopIcons.check);
        }
      } on Object catch (error) {
        if (context.mounted) {
          showDesktopToast(
            context,
            failureToast(l10n, l10n.settingsNotification, error),
            kind: DesktopToastKind.error,
            icon: DesktopIcons.info,
          );
        }
      }
    }

    final typeCodes = <String>[
      ..._knownTypeCodes,
      for (final code in prefs.types.keys)
        if (!_knownTypeCodes.contains(code)) code,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Card(
          title: l10n.settingsNotification,
          subtitle: l10n.desktopNotificationSettings,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SettingToggleRow(
                label: l10n.settingsNotificationEnable,
                hint: l10n.settingsNotificationEnableHint,
                value: prefs.enabled,
                onChanged: (value) => save(prefs.copyWith(enabled: value)),
              ),
              _SettingToggleRow(
                label: l10n.profileNotificationSound,
                hint: l10n.profileNotificationSoundHint,
                value: prefs.sound,
                onChanged: (value) => save(prefs.copyWith(sound: value)),
              ),
              _SettingToggleRow(
                label: l10n.profileNotificationPreview,
                hint: l10n.profileNotificationPreviewHint,
                value: prefs.showPreview,
                onChanged: (value) => save(prefs.copyWith(showPreview: value)),
              ),
              _SettingToggleRow(
                label: l10n.desktopSettingsForegroundBanner,
                hint: l10n.notificationForegroundToastToggleSubtitle,
                value: prefs.foregroundBanner,
                onChanged:
                    (value) => save(prefs.copyWith(foregroundBanner: value)),
              ),
              _SettingToggleRow(
                label: l10n.profileNotificationEmail,
                hint: l10n.profileNotificationEmailHint,
                value: prefs.emailNotification,
                onChanged:
                    (value) => save(prefs.copyWith(emailNotification: value)),
              ),
              _SettingToggleRow(
                label: l10n.notificationQuietHours,
                hint: l10n.notificationQuietHoursHint,
                value: prefs.quietHours.enabled,
                onChanged:
                    (value) => save(
                      prefs.copyWith(
                        quietHours: prefs.quietHours.copyWith(enabled: value),
                      ),
                    ),
              ),
              if (prefs.quietHours.enabled)
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 4),
                  child: _DesktopQuietHoursFields(
                    start: prefs.quietHours.start,
                    end: prefs.quietHours.end,
                    onChanged: (start, end) {
                      unawaited(
                        save(
                          prefs.copyWith(
                            quietHours: prefs.quietHours.copyWith(
                              start: start,
                              end: end,
                            ),
                          ),
                          successMessage:
                              '${l10n.notificationQuietHours} · $start – $end',
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _Card(
          title: l10n.notificationTypesHeader,
          child: IgnorePointer(
            ignoring: !prefs.enabled,
            child: Opacity(
              opacity: prefs.enabled ? 1.0 : 0.48,
              alwaysIncludeSemantics: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final code in typeCodes)
                    _SettingToggleRow(
                      label: _desktopNotificationTypeLabel(code, l10n),
                      hint: _desktopNotificationTypeDescription(code, l10n),
                      value: prefs.isTypeEnabled(code),
                      onChanged: (value) {
                        final nextTypes = Map<String, bool>.from(prefs.types)
                          ..[code] = value;
                        unawaited(save(prefs.copyWith(types: nextTypes)));
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DesktopQuietHoursFields extends StatelessWidget {
  const _DesktopQuietHoursFields({
    required this.start,
    required this.end,
    required this.onChanged,
  });

  final String start;
  final String end;
  final void Function(String start, String end) onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: _DesktopQuietTimeField(
            label: l10n.notificationQuietHoursStart,
            value: start,
            onTap: () => _pick(context, isStart: true),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _DesktopQuietTimeField(
            label: l10n.notificationQuietHoursEnd,
            value: end,
            onTap: () => _pick(context, isStart: false),
          ),
        ),
      ],
    );
  }

  Future<void> _pick(BuildContext context, {required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _parseQuietHoursTime(isStart ? start : end),
    );
    if (picked == null) {
      return;
    }
    final formatted = _formatQuietHoursTime(picked);
    if (isStart) {
      if (formatted != start) {
        onChanged(formatted, end);
      }
    } else {
      if (formatted != end) {
        onChanged(start, formatted);
      }
    }
  }
}

class _DesktopQuietTimeField extends StatelessWidget {
  const _DesktopQuietTimeField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return DesktopHover(
      builder: (context, hovered) {
        return GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: DesktopMotion.fast,
            curve: DesktopMotion.ease,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: hovered ? skin.raise2 : skin.raise,
              borderRadius: BorderRadius.circular(DesktopMetrics.radiusButton),
              border: Border.all(color: hovered ? skin.line2 : skin.line),
            ),
            child: Row(
              children: [
                Icon(DesktopIcons.clock, size: 15, color: skin.text3),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DesktopType.caption(skin.text3),
                  ),
                ),
                const SizedBox(width: 8),
                Text(value, style: DesktopType.bodyStrong(skin.text)),
              ],
            ),
          ),
        );
      },
    );
  }
}

TimeOfDay _parseQuietHoursTime(String value) {
  final parts = value.split(':');
  if (parts.length != 2) {
    return const TimeOfDay(hour: 22, minute: 0);
  }
  final hour = int.tryParse(parts[0].trim());
  final minute = int.tryParse(parts[1].trim());
  if (hour == null ||
      minute == null ||
      hour < 0 ||
      hour > 23 ||
      minute < 0 ||
      minute > 59) {
    return const TimeOfDay(hour: 22, minute: 0);
  }
  return TimeOfDay(hour: hour, minute: minute);
}

String _formatQuietHoursTime(TimeOfDay time) {
  return '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';
}

String _desktopNotificationTypeLabel(String typeCode, AppLocalizations l10n) {
  return switch (typeCode) {
    'TASK_COMPLETED' => l10n.notificationTypeTaskCompleted,
    'TASK_FAILED' => l10n.notificationTypeTaskFailed,
    'SHARE_ACCESS' => l10n.notificationTypeShareAccess,
    'SYSTEM_MESSAGE' => l10n.notificationTypeSystemMessage,
    'MEDIA_SCRAPED' => l10n.notificationTypeMetadataScrape,
    'SHARE_ACCESSED' => l10n.notificationTypeShareVisited,
    'QUOTA_WARNING' => l10n.notificationTypeStorageWarning,
    'NEW_DEVICE_LOGIN' => l10n.notificationTypeNewDeviceLogin,
    'PASSWORD_CHANGED' => l10n.notificationTypePasswordChanged,
    'SECURITY_THREAT' => l10n.notificationTypeSecurityThreat,
    'SECURITY_SCAN_FAILED' => l10n.notificationTypeSecurityScanFailed,
    'MEDIA_AUTO_IMPORT_COMPLETED' => l10n.notificationTypeMediaImportCompleted,
    'MEDIA_AUTO_IMPORT_FAILED' => l10n.notificationTypeMediaImportFailed,
    _ => typeCode,
  };
}

String _desktopNotificationTypeDescription(
  String typeCode,
  AppLocalizations l10n,
) {
  return switch (typeCode) {
    'TASK_COMPLETED' => l10n.notificationTypeTaskCompletedDesc,
    'TASK_FAILED' => l10n.notificationTypeTaskFailedDesc,
    'SHARE_ACCESS' => l10n.notificationTypeShareAccessDesc,
    'SYSTEM_MESSAGE' => l10n.notificationTypeSystemMessageDesc,
    'MEDIA_SCRAPED' => l10n.notificationTypeMetadataScrapeDesc,
    'SHARE_ACCESSED' => l10n.notificationTypeShareVisitedDesc,
    'QUOTA_WARNING' => l10n.notificationTypeStorageWarningDesc,
    'NEW_DEVICE_LOGIN' => l10n.notificationTypeNewDeviceLoginDesc,
    'PASSWORD_CHANGED' => l10n.notificationTypePasswordChangedDesc,
    'SECURITY_THREAT' => l10n.notificationTypeSecurityThreatDesc,
    'SECURITY_SCAN_FAILED' => l10n.notificationTypeSecurityScanFailedDesc,
    'MEDIA_AUTO_IMPORT_COMPLETED' =>
      l10n.notificationTypeMediaImportCompletedDesc,
    'MEDIA_AUTO_IMPORT_FAILED' => l10n.notificationTypeMediaImportFailedDesc,
    _ => '',
  };
}

class _SettingToggleRow extends StatelessWidget {
  const _SettingToggleRow({
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: skin.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: DesktopType.bodyStrong(skin.text)),
                const SizedBox(height: 2),
                Text(hint, style: DesktopType.caption(skin.text3)),
              ],
            ),
          ),
          DesktopToggle(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// 关于与更新：展示版本、服务器地址，并可主动检查新版本。
