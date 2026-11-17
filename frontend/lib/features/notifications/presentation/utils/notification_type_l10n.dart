import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/notifications/domain/notification_models.dart';

/// 通知类型 typeCode 到本地化标签的映射。
String notificationTypeLabel(String typeCode, AppLocalizations l10n) {
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

/// 通知类型 typeCode 到工位卡片图标的映射。
IconData notificationTypeIcon(String typeCode) {
  return switch (typeCode) {
    'TASK_COMPLETED' => Icons.task_alt_outlined,
    'TASK_FAILED' => Icons.error_outline_rounded,
    'SHARE_ACCESS' || 'SHARE_ACCESSED' => Icons.share_outlined,
    'SYSTEM_MESSAGE' => Icons.info_outline_rounded,
    'MEDIA_SCRAPED' => Icons.video_library_outlined,
    'QUOTA_WARNING' => Icons.warning_amber_outlined,
    'NEW_DEVICE_LOGIN' => Icons.shield_outlined,
    'PASSWORD_CHANGED' => Icons.lock_outline_rounded,
    'SECURITY_THREAT' => Icons.security_outlined,
    'SECURITY_SCAN_FAILED' => Icons.health_and_safety_outlined,
    'MEDIA_AUTO_IMPORT_COMPLETED' => Icons.task_alt_outlined,
    'MEDIA_AUTO_IMPORT_FAILED' => Icons.error_outline_rounded,
    _ => Icons.notifications_none_rounded,
  };
}

/// 通知类型 typeCode 到本地化描述的映射。
String? notificationTypeDescription(String typeCode, AppLocalizations l10n) {
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
    _ => null,
  };
}

/// 语义通知（后端只落类型与元数据、不落文案）的展示文案合成。
///
/// 返回 null 表示该通知不属于可合成类型，调用方回退到 title/message
/// 或既有占位逻辑。
String? synthesizedNotificationText(
  NotificationDto notification,
  AppLocalizations l10n,
) {
  if (notification.title?.isNotEmpty == true ||
      notification.message?.isNotEmpty == true) {
    return null;
  }
  final fileName = notification.metadata['fileName']?.toString();
  final hasName = fileName != null && fileName.isNotEmpty;
  return switch (notification.type) {
    'MEDIA_AUTO_IMPORT_COMPLETED' =>
      hasName
          ? l10n.notificationMediaImportCompletedWithName(fileName)
          : l10n.notificationMediaImportCompleted,
    'MEDIA_AUTO_IMPORT_FAILED' =>
      hasName
          ? l10n.notificationMediaImportFailedWithName(fileName)
          : l10n.notificationMediaImportFailed,
    _ => null,
  };
}
