import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/platform/android/photo_backup_scheduling.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 照片后台备份开关的本地偏好键。
const String photoBackupBackgroundEnabledKey =
    'photo.backup.background_enabled';

final photoBackupPreferencesControllerProvider =
    AsyncNotifierProvider<PhotoBackupPreferencesController, bool>(
      PhotoBackupPreferencesController.new,
    );

/// 照片后台备份开关：开启时注册 WorkManager 周期任务，关闭时取消。
class PhotoBackupPreferencesController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(photoBackupBackgroundEnabledKey) ?? false;
  }

  Future<void> setEnabled(bool enabled) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(photoBackupBackgroundEnabledKey, enabled);
      await syncPhotoBackupScheduling(enabled);
      return enabled;
    });
  }
}

/// 启动期按已保存偏好恢复备份调度；Web/桌面端为空实现。
///
/// true/false 都调用 sync，保证关闭偏好时也会取消残留 WorkManager 任务。
Future<void> restorePhotoBackupSchedulingFromPreferences() async {
  final prefs = await SharedPreferences.getInstance();
  final enabled = prefs.getBool(photoBackupBackgroundEnabledKey) ?? false;
  await syncPhotoBackupScheduling(enabled);
}
