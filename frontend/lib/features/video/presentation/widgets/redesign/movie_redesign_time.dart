import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';

/// 新版设计的相对时间文案：分钟/小时/天前，超过一周回退日期。
String movieRedesignRelativeTime(BuildContext context, DateTime? time) {
  if (time == null) {
    return '';
  }
  final l10n = AppLocalizations.of(context);
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) {
    return l10n.tasksTimeMinutesAgo(0);
  }
  if (diff.inMinutes < 60) {
    return l10n.tasksTimeMinutesAgo(diff.inMinutes);
  }
  if (diff.inHours < 24) {
    return l10n.tasksTimeHoursAgo(diff.inHours);
  }
  if (diff.inDays < 7) {
    return l10n.tasksTimeDaysAgo(diff.inDays);
  }
  final now = DateTime.now();
  final sameYear = time.year == now.year;
  final month = time.month.toString().padLeft(2, '0');
  final day = time.day.toString().padLeft(2, '0');
  return sameYear ? '$month-$day' : '${time.year}-$month-$day';
}

/// 秒数转"Xh Ym"样式的等宽时长文案。
String movieRedesignFormatDuration(int seconds) {
  if (seconds <= 0) {
    return '';
  }
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) / 60;
  if (hours <= 0) {
    return '${minutes.round()}m';
  }
  return '${hours}h ${minutes.round()}m';
}
