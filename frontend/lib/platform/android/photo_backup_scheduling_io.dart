import 'dart:io';

import 'package:omninest/platform/android/android_background_sync.dart';

/// Android 照片备份调度：开启注册周期任务，关闭取消；其余平台空操作。
Future<void> syncPhotoBackupScheduling(bool enabled) async {
  if (!Platform.isAndroid) {
    return;
  }
  final sync = AndroidBackgroundSync();
  if (enabled) {
    await sync.registerPeriodicBackup();
  } else {
    await sync.cancelBackup();
  }
}
