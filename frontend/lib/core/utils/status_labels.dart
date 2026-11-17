import 'package:omninest/app/l10n/app_localizations.dart';

/// 后端状态/枚举值的本地化标签映射。
///
/// 覆盖存储位置与视频库源的状态字段；未知值原样返回，
/// 保证后端新增枚举时界面不至于空白。
/// 供 admin 媒体库聚合页与 video 模块共用，替代各处私有映射。
// ignore_for_file: avoid_non_null_assertion

String healthStatusLabel(AppLocalizations l10n, String healthStatus) {
  return switch (healthStatus.toUpperCase()) {
    'HEALTHY' => l10n.statusHealthHealthy,
    'AVAILABLE' => l10n.statusHealthAvailable,
    'UNAVAILABLE' => l10n.statusHealthUnavailable,
    'DISABLED' => l10n.adminStatusDisabled,
    _ => healthStatus,
  };
}

String scopeTypeLabel(AppLocalizations l10n, String scopeType) {
  return switch (scopeType.toUpperCase()) {
    'PERSONAL' => l10n.statusScopePersonal,
    'SHARED' => l10n.statusScopeShared,
    _ => scopeType,
  };
}

String providerTypeLabel(AppLocalizations l10n, String providerType) {
  return switch (providerType.toUpperCase()) {
    'LOCAL_FILESYSTEM' => l10n.statusProviderLocalFilesystem,
    'MINIO' => l10n.statusProviderMinio,
    _ => providerType,
  };
}

String managementModeLabel(AppLocalizations l10n, String managementMode) {
  return switch (managementMode.toUpperCase()) {
    'MANAGED' => l10n.statusManagementManaged,
    _ => managementMode,
  };
}

String scanStatusLabel(AppLocalizations l10n, String scanStatus) {
  return switch (scanStatus.toUpperCase()) {
    'READY' => l10n.statusScanReady,
    'QUEUED' => l10n.statusScanQueued,
    'DISCOVERING' => l10n.statusScanDiscovering,
    'APPLYING' => l10n.statusScanApplying,
    'FAILED' => l10n.statusScanFailed,
    'CANCELLED' => l10n.statusScanCancelled,
    'PAUSED' => l10n.statusScanPaused,
    'PARTIAL' => l10n.statusScanPartial,
    _ => scanStatus,
  };
}

String scanPhaseLabel(AppLocalizations l10n, String phase) {
  return switch (phase.toUpperCase()) {
    'DISCOVERY' => l10n.statusPhaseDiscovery,
    'REVIEW' => l10n.statusPhaseReview,
    'APPLY' => l10n.statusPhaseApply,
    _ => phase,
  };
}
