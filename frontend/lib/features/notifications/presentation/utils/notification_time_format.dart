import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';

/// 通知时间的相对格式（刚刚 / n 分钟 / n 小时 / n 天 / 日期），供
/// 桌面工位卡与移动面板行共用，保证两端时间文案一致。
String formatNotificationTime(BuildContext context, DateTime dateTime) {
  final l10n = AppLocalizations.of(context);
  final diff = DateTime.now().difference(dateTime);
  if (diff.inMinutes < 1) {
    return l10n.notificationTimeNow;
  }
  if (diff.inHours < 1) {
    return l10n.notificationTimeMinutes(diff.inMinutes);
  }
  if (diff.inDays < 1) {
    return l10n.notificationTimeHours(diff.inHours);
  }
  if (diff.inDays < 7) {
    return l10n.notificationTimeDays(diff.inDays);
  }
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return '${dateTime.year}-${twoDigits(dateTime.month)}-${twoDigits(dateTime.day)} ${twoDigits(dateTime.hour)}:${twoDigits(dateTime.minute)}';
}
