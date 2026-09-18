import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop.dart';
import 'package:path_provider/path_provider.dart';
import 'package:omninest/core/log/dev_log.dart';

/// IO 平台的内置默认壁纸登记。
///
/// v2 起内置壁纸为打包静态图,渲染直接走 [Image.asset],不再复制本机
/// 文件;此处仅登记素材元数据并清理 v1 动态壁纸遗留的本机拷贝。
class AppBackdropBundledAssetInstaller {
  static const String _legacyFileName = 'default_wallpaper_v1.mp4';

  /// 登记内置默认壁纸并返回背景库素材。
  Future<AppBackdropAsset?> install() async {
    await _cleanUpLegacyVideoFile();
    final now = DateTime.now();
    return AppBackdropAsset(
      id: bundledDefaultWallpaperId,
      path: bundledDefaultWallpaperAssetPath,
      title: 'OmniNest',
      mediaType: AppBackdropMediaType.image,
      sourceType: AppBackdropSourceType.bundled,
      fileSize: 0,
      modifiedAt: now,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<void> _cleanUpLegacyVideoFile() async {
    try {
      final supportDirectory = await getApplicationSupportDirectory();
      final legacy = File(
        '${supportDirectory.path}${Platform.pathSeparator}backdrops'
        '${Platform.pathSeparator}$_legacyFileName',
      );
      if (await legacy.exists()) {
        await legacy.delete();
      }
    } on Object catch (error) {
      if (kDebugMode) {
        devLog('内置壁纸 v1 遗留文件清理失败(忽略): $error');
      }
    }
  }
}
