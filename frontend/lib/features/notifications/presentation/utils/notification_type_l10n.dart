import 'package:omninest/app/l10n/app_localizations.dart';

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
    _ => typeCode,
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
    _ => null,
  };
}
