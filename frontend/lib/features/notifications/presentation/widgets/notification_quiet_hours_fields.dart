import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';

/// 免打扰起止时间编辑：两个细线框按钮，点击弹出系统时间选择器。
///
/// 工位分区卡与移动行共用本控件，保证三端写入同一份服务端偏好；
/// 时段生效判定在 `NotificationPreferences.isQuietAt`，这里只做取值。
class NotificationQuietHoursFields extends StatelessWidget {
  const NotificationQuietHoursFields({
    required this.start,
    required this.end,
    required this.enabled,
    required this.onChanged,
    this.padding = const EdgeInsets.fromLTRB(20, 2, 20, 10),
    super.key,
  });

  final String start;
  final String end;

  /// 免打扰关闭时按钮不可点，避免改完时段却忘了开开关。
  final bool enabled;
  final void Function(String start, String end) onChanged;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: _QuietTimeField(
              label: l10n.notificationQuietHoursStart,
              value: start,
              onTap: enabled ? () => _pick(context, isStart: true) : null,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _QuietTimeField(
              label: l10n.notificationQuietHoursEnd,
              value: end,
              onTap: enabled ? () => _pick(context, isStart: false) : null,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pick(BuildContext context, {required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _parseTime(isStart ? start : end),
    );
    if (picked == null) {
      return;
    }
    final value = _formatTime(picked);
    if (isStart) {
      onChanged(value, end);
    } else {
      onChanged(start, value);
    }
  }
}

class _QuietTimeField extends StatelessWidget {
  const _QuietTimeField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        // 只描边不填充：工位与移动壳层主题不同底，透明底在两种主题下都成立。
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppTypography.labelSmall,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: AppTypography.bodySmall,
                color:
                    enabled
                        ? scheme.onSurface
                        : scheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

TimeOfDay _parseTime(String value) {
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

String _formatTime(TimeOfDay time) {
  return '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';
}
