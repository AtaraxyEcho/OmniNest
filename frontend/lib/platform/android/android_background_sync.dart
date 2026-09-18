import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/preferences/app_bootstrap_data.dart';
import 'package:omninest/features/files/data/file_providers.dart';
import 'package:omninest/features/files/domain/file_repository.dart';
import 'package:omninest/features/photos/application/photo_backup_preferences.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/platform/android/android_photo_backup.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

/// 后台备份任务名称
const String _backupTaskName = 'omninest.photo.backup';

/// 上传文件到服务器
Future<void> _uploadFile(FileRepository repository, String filePath) async {
  final file = File(filePath);
  final fileName = filePath.split(Platform.pathSeparator).last;
  final sizeBytes = await file.length();

  // 创建上传会话
  final session = await repository.createUploadSession(
    fileName: fileName,
    sizeBytes: sizeBytes,
    mimeType: 'application/octet-stream',
  );

  if (session.isDirectUpload) {
    // 直传模式：直接上传整个文件
    final stream = file.openRead();
    await repository.putUploadUrl(
      uploadUrl: session.uploadUrl!,
      data: stream,
      contentLength: sizeBytes,
    );
  } else {
    // 分片上传模式
    final stream = file.openRead();
    int partIndex = 0;

    await for (final chunk in stream) {
      if (partIndex >= session.parts.length) break;
      final part = session.parts[partIndex];
      final chunkStream = Stream<List<int>>.value(chunk);
      final eTag = await repository.putUploadUrl(
        uploadUrl: part.uploadUrl!,
        data: chunkStream,
        contentLength: chunk.length,
      );
      await repository.completeUploadPart(
        uploadId: session.uploadId,
        partNumber: part.partNumber,
        eTag: eTag,
      );
      partIndex++;
    }
  }

  // 完成上传会话
  await repository.completeUploadSession(sessionId: session.uploadId);
}

/// 后台任务按设备偏好语言加载文案。
Future<AppLocalizations> _loadAppLocalizations() async {
  final prefs = await SharedPreferences.getInstance();
  final code = prefs.getString(localeDeviceLanguageKey) ?? 'zh';
  final locale = Locale(code);
  return AppLocalizations.delegate.load(locale);
}

/// WorkManager 回调入口（必须为顶层函数）
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != _backupTaskName) return true;

    ProviderContainer? container;
    try {
      WidgetsFlutterBinding.ensureInitialized();
      container = ProviderContainer();
      final l10n = await _loadAppLocalizations();
      final deviceId = await AndroidBackgroundSync.getDeviceId();
      final backupSettings = await readPhotoBackupSettings();
      final photoApi = container.read(photoApiProvider);
      final fileRepository = container.read(fileRepositoryProvider);
      final backupService = AndroidPhotoBackupService(
        photoApi: photoApi,
        onUpload: (filePath) => _uploadFile(fileRepository, filePath),
        l10n: l10n,
      );
      final result = await backupService.runBackup(
        deviceId: deviceId,
        scope: backupSettings.scope,
        selectedAlbumIds: backupSettings.selectedAlbumIds,
      );
      return result.status != BackupStatus.failure;
    } catch (e) {
      return false;
    } finally {
      container?.dispose();
    }
  });
}

/// Android 后台同步管理
class AndroidBackgroundSync {
  /// 注册定期备份任务
  Future<void> registerPeriodicBackup() async {
    if (!Platform.isAndroid) return;

    await Workmanager().initialize(callbackDispatcher);
    await Workmanager().registerPeriodicTask(
      _backupTaskName,
      _backupTaskName,
      frequency: const Duration(hours: 6),
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true,
      ),
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 15),
    );
  }

  /// 取消备份任务
  Future<void> cancelBackup() async {
    if (!Platform.isAndroid) return;
    await Workmanager().cancelByUniqueName(_backupTaskName);
  }

  /// 手动触发一次备份
  Future<void> triggerOneTimeBackup() async {
    if (!Platform.isAndroid) return;
    await Workmanager().registerOneOffTask(
      '$_backupTaskName.manual',
      _backupTaskName,
      constraints: Constraints(networkType: NetworkType.connected),
    );
  }

  /// 获取设备 ID
  static Future<String> getDeviceId() async {
    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      return androidInfo.id;
    }
    return 'unknown';
  }
}
