import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/photos/application/photo_backup_preferences.dart';
import 'package:omninest/features/photos/data/photo_api.dart';
import 'package:photo_manager/photo_manager.dart';

/// Android 设备照片自动备份服务
///
/// 枚举设备照片 → 计算哈希 → 跳过已备份 → 上传新照片 → 通知进度。
/// 范围由偏好决定：全部相册（聚合桶）或仅用户自选的相册集合。
class AndroidPhotoBackupService {
  AndroidPhotoBackupService({
    required this.photoApi,
    required this.onUpload,
    required this.l10n,
  });

  final PhotoApi photoApi;
  final Future<void> Function(String filePath) onUpload;
  final AppLocalizations l10n;

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static const int _notificationId = 202601;
  static const int _batchSize = 20;

  /// 执行备份流程
  Future<BackupResult> runBackup({
    required String deviceId,
    PhotoBackupScope scope = PhotoBackupScope.all,
    Set<String> selectedAlbumIds = const <String>{},
  }) async {
    // 检查网络：仅 WiFi 时备份
    final connectivity = await Connectivity().checkConnectivity();
    if (!connectivity.contains(ConnectivityResult.wifi)) {
      return BackupResult.skipped(l10n.backupSkipNonWifi);
    }

    // 初始化通知
    await _initNotifications();

    // 获取设备照片列表
    final PermissionState permission =
        await PhotoManager.requestPermissionExtend();
    if (!permission.isAuth) {
      return BackupResult.skipped(l10n.backupSkipNoPermission);
    }

    final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      hasAll: true,
    );
    if (albums.isEmpty) {
      return BackupResult.skipped(l10n.backupSkipNoAlbums);
    }

    // 范围过滤：自选仅枚举勾选相册；全部沿用「全部照片」聚合桶。
    final List<AssetPathEntity> targets;
    if (scope == PhotoBackupScope.selected) {
      targets =
          albums
              .where(
                (album) => !album.isAll && selectedAlbumIds.contains(album.id),
              )
              .toList();
      if (targets.isEmpty) {
        return BackupResult.skipped(l10n.backupSkipNoAlbums);
      }
    } else {
      targets = [albums.first];
    }

    int totalCount = 0;
    for (final album in targets) {
      totalCount += await album.assetCountAsync;
    }
    if (totalCount == 0) {
      return BackupResult.skipped(l10n.backupSkipNoPhotos);
    }

    // 分批处理
    int uploaded = 0;
    int skipped = 0;
    int failed = 0;
    int processed = 0;

    for (final album in targets) {
      final int albumCount = await album.assetCountAsync;
      for (int offset = 0; offset < albumCount; offset += _batchSize) {
        final List<AssetEntity> assets = await album.getAssetListPaged(
          page: offset ~/ _batchSize,
          size: _batchSize,
        );

        // 计算哈希
        final Map<String, AssetEntity> hashMap = {};
        for (final asset in assets) {
          try {
            final File? file = await asset.file;
            if (file == null) continue;
            final String hash = await _computeHash(file);
            hashMap[hash] = asset;
          } catch (_) {
            failed++;
          }
        }

        // 查询已备份的哈希
        final List<String> existingHashes = await photoApi.checkDuplicate(
          hashMap.keys.toList(),
        );
        final Set<String> existingSet = existingHashes.toSet();

        // 上传新照片
        for (final entry in hashMap.entries) {
          if (existingSet.contains(entry.key)) {
            skipped++;
            continue;
          }
          try {
            final File? file = await entry.value.file;
            if (file == null) {
              failed++;
              continue;
            }
            await onUpload(file.path);
            uploaded++;
          } catch (_) {
            failed++;
          }
        }

        // 更新通知进度
        processed += assets.length;
        await _showProgress(
          current: processed,
          total: totalCount,
          uploaded: uploaded,
        );
      }
    }

    // 上报备份状态
    await photoApi.reportBackup(deviceId, uploaded);

    // 完成通知
    await _showComplete(uploaded: uploaded, skipped: skipped, failed: failed);

    return BackupResult.success(
      uploaded: uploaded,
      skipped: skipped,
      failed: failed,
    );
  }

  /// 计算文件 SHA-256 哈希
  Future<String> _computeHash(File file) async {
    final Digest digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  /// 初始化通知渠道
  Future<void> _initNotifications() async {
    const AndroidInitializationSettings android = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const InitializationSettings settings = InitializationSettings(
      android: android,
    );
    await _notifications.initialize(settings);
  }

  /// 显示进度通知
  Future<void> _showProgress({
    required int current,
    required int total,
    required int uploaded,
  }) async {
    final AndroidNotificationDetails android = AndroidNotificationDetails(
      'photo_backup',
      l10n.backupNotificationChannel,
      channelDescription: l10n.backupNotificationChannelDesc,
      importance: Importance.low,
      priority: Priority.low,
      showProgress: true,
      maxProgress: 100,
      ongoing: true,
    );
    final NotificationDetails details = NotificationDetails(android: android);
    await _notifications.show(
      _notificationId,
      l10n.backupNotificationTitle,
      l10n.backupNotificationProgress(current, total, uploaded),
      details,
      payload: 'progress',
    );
  }

  /// 显示完成通知
  Future<void> _showComplete({
    required int uploaded,
    required int skipped,
    required int failed,
  }) async {
    final AndroidNotificationDetails android = AndroidNotificationDetails(
      'photo_backup',
      l10n.backupNotificationChannel,
      channelDescription: l10n.backupNotificationChannelDesc,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    final NotificationDetails details = NotificationDetails(android: android);
    await _notifications.show(
      _notificationId,
      l10n.backupNotificationComplete,
      l10n.backupNotificationSummary(uploaded, skipped, failed),
      details,
      payload: 'complete',
    );
  }
}

/// 备份结果
class BackupResult {
  const BackupResult._({
    required this.status,
    this.uploaded = 0,
    this.skipped = 0,
    this.failed = 0,
    this.reason,
  });

  factory BackupResult.success({
    required int uploaded,
    required int skipped,
    required int failed,
  }) {
    return BackupResult._(
      status: BackupStatus.success,
      uploaded: uploaded,
      skipped: skipped,
      failed: failed,
    );
  }

  factory BackupResult.skipped(String reason) {
    return BackupResult._(status: BackupStatus.skipped, reason: reason);
  }

  factory BackupResult.failure(String reason) {
    return BackupResult._(status: BackupStatus.failure, reason: reason);
  }

  final BackupStatus status;
  final int uploaded;
  final int skipped;
  final int failed;
  final String? reason;
}

enum BackupStatus { success, skipped, failure }
