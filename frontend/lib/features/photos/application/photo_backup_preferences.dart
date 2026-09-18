import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/platform/android/photo_backup_scheduling.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 照片后台备份开关的本地偏好键。
const String photoBackupBackgroundEnabledKey =
    'photo.backup.background_enabled';

/// 备份范围键：all=全部相册（存量与缺省值），selected=仅自选相册。
const String photoBackupScopeKey = 'photo.backup.scope';

/// 自选相册 ID 集合键（scope=selected 时生效）。
const String photoBackupSelectedAlbumIdsKey = 'photo.backup.selected_album_ids';

/// 网络策略键：wifiOnly=仅不限流量网络（缺省），any=含移动网络。
const String photoBackupNetworkPolicyKey = 'photo.backup.network_policy';

/// 备份范围。
enum PhotoBackupScope { all, selected }

/// 备份网络策略。
enum PhotoBackupNetworkPolicy { wifiOnly, any }

/// 备份设置快照：开关 + 范围 + 自选相册集合 + 网络策略。
class PhotoBackupSettings {
  const PhotoBackupSettings({
    required this.enabled,
    required this.scope,
    required this.selectedAlbumIds,
    required this.networkPolicy,
  });

  final bool enabled;
  final PhotoBackupScope scope;
  final Set<String> selectedAlbumIds;
  final PhotoBackupNetworkPolicy networkPolicy;
}

final photoBackupPreferencesControllerProvider = AsyncNotifierProvider<
  PhotoBackupPreferencesController,
  PhotoBackupSettings
>(PhotoBackupPreferencesController.new);

/// 照片后台备份偏好：开启必须携带范围（经确认弹窗），关闭取消调度。
class PhotoBackupPreferencesController
    extends AsyncNotifier<PhotoBackupSettings> {
  @override
  Future<PhotoBackupSettings> build() async {
    final prefs = await SharedPreferences.getInstance();
    return readPhotoBackupSettingsFrom(prefs);
  }

  /// 开启备份并记录范围与网络策略；自选范围至少含一个相册由 UI 校验。
  Future<void> enable({
    required PhotoBackupScope scope,
    required Set<String> selectedAlbumIds,
    PhotoBackupNetworkPolicy networkPolicy = PhotoBackupNetworkPolicy.wifiOnly,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(photoBackupBackgroundEnabledKey, true);
      await prefs.setString(photoBackupScopeKey, scope.name);
      await prefs.setStringList(
        photoBackupSelectedAlbumIdsKey,
        selectedAlbumIds.toList(),
      );
      await prefs.setString(photoBackupNetworkPolicyKey, networkPolicy.name);
      await syncPhotoBackupScheduling(true);
      return readPhotoBackupSettingsFrom(prefs);
    });
  }

  /// 关闭备份；范围偏好保留，便于再次开启时复用。
  Future<void> disable() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(photoBackupBackgroundEnabledKey, false);
      await syncPhotoBackupScheduling(false);
      return readPhotoBackupSettingsFrom(prefs);
    });
  }

  /// 调整网络策略（仅 Wi-Fi / 含移动网络）；不影响调度注册，仅运行时生效。
  Future<void> setNetworkPolicy(PhotoBackupNetworkPolicy policy) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(photoBackupNetworkPolicyKey, policy.name);
      return readPhotoBackupSettingsFrom(prefs);
    });
  }
}

/// 从偏好存储解析备份设置；范围键缺省视为 all、网络策略缺省视为
/// wifiOnly（兼容升级前已开启的存量用户）。
PhotoBackupSettings readPhotoBackupSettingsFrom(SharedPreferences prefs) {
  final enabled = prefs.getBool(photoBackupBackgroundEnabledKey) ?? false;
  final scope =
      prefs.getString(photoBackupScopeKey) == PhotoBackupScope.selected.name
          ? PhotoBackupScope.selected
          : PhotoBackupScope.all;
  final selectedAlbumIds =
      prefs.getStringList(photoBackupSelectedAlbumIdsKey) ?? const [];
  final networkPolicy =
      prefs.getString(photoBackupNetworkPolicyKey) ==
              PhotoBackupNetworkPolicy.any.name
          ? PhotoBackupNetworkPolicy.any
          : PhotoBackupNetworkPolicy.wifiOnly;
  return PhotoBackupSettings(
    enabled: enabled,
    scope: scope,
    selectedAlbumIds: selectedAlbumIds.toSet(),
    networkPolicy: networkPolicy,
  );
}

/// 读取当前生效的备份设置（供后台任务独立于 Provider 生命周期使用）。
Future<PhotoBackupSettings> readPhotoBackupSettings() async {
  final prefs = await SharedPreferences.getInstance();
  return readPhotoBackupSettingsFrom(prefs);
}

/// 启动期按已保存偏好恢复备份调度；Web/桌面端为空实现。
///
/// true/false 都调用 sync，保证关闭偏好时也会取消残留 WorkManager 任务。
Future<void> restorePhotoBackupSchedulingFromPreferences() async {
  final prefs = await SharedPreferences.getInstance();
  final settings = readPhotoBackupSettingsFrom(prefs);
  await syncPhotoBackupScheduling(settings.enabled);
}
