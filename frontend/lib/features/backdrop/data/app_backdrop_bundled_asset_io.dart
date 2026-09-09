import 'dart:io';

import 'package:flutter/services.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop.dart';
import 'package:path_provider/path_provider.dart';

/// 将安装包内置动态壁纸安装为背景库可读取的本机文件。
class AppBackdropBundledAssetInstaller {
  static const String assetPath = 'assets/backdrops/default_wallpaper.mp4';
  static const String fileName = 'default_wallpaper_v1.mp4';

  /// 安装内置动态壁纸并返回背景库素材。
  Future<AppBackdropAsset?> install() async {
    final supportDirectory = await getApplicationSupportDirectory();
    final backdropDirectory = Directory(
      '${supportDirectory.path}${Platform.pathSeparator}backdrops',
    );
    await backdropDirectory.create(recursive: true);
    final target = File(
      '${backdropDirectory.path}${Platform.pathSeparator}$fileName',
    );
    final targetReady = await target.exists() && await target.length() > 0;
    if (!targetReady) {
      final data = await rootBundle.load(assetPath);
      await target.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }

    final stat = await target.stat();
    final now = DateTime.now();
    return AppBackdropAsset(
      id: bundledDefaultWallpaperId,
      path: target.path,
      title: 'OmniNest',
      mediaType: AppBackdropMediaType.video,
      sourceType: AppBackdropSourceType.bundled,
      fileSize: stat.size,
      modifiedAt: stat.modified,
      createdAt: now,
      updatedAt: now,
    );
  }
}
