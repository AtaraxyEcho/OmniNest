import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:omninest/core/log/dev_log.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop.dart';
import 'package:path_provider/path_provider.dart';

/// IO 平台的内置默认壁纸登记。
///
/// 内置壁纸是一段打包视频：media_kit 只能打开真实文件或网络地址，因此首次
/// 登记时把资产落一份到应用支持目录，之后直接复用。文件名带版本号——替换素材
/// 时改版本号，旧拷贝即自然失效并被清理，不必逐字节比对资产。
class AppBackdropBundledAssetInstaller {
  /// 当前内置壁纸的落盘文件名。素材替换时必须递增版本号。
  static const String _fileName = 'bundled_default_wallpaper_v3.mp4';

  /// v1 曾把动态壁纸拷进同一目录，升级后残留文件不再被引用。
  static const String _legacyFileName = 'default_wallpaper_v1.mp4';

  /// 登记内置默认壁纸并返回背景库素材。
  Future<AppBackdropAsset?> install() async {
    await _cleanUpLegacyFiles();
    final now = DateTime.now();
    final file = await _ensureBundledVideoFile();
    // 落盘失败时退回打包资产地址：视频打不开，但封面帧仍能垫底，
    // 比让默认壁纸整块消失更接近预期。
    return AppBackdropAsset(
      id: bundledDefaultWallpaperId,
      path: file?.path ?? bundledDefaultWallpaperAssetPath,
      title: 'OmniNest',
      mediaType: AppBackdropMediaType.video,
      sourceType: AppBackdropSourceType.bundled,
      fileSize: file == null ? 0 : await _lengthOrZero(file),
      modifiedAt: now,
      createdAt: now,
      updatedAt: now,
      localVideoPath: file?.path,
      thumbnailPath: bundledDefaultWallpaperPosterAssetPath,
    );
  }

  /// 确保打包视频在支持目录里有一份完整拷贝。
  Future<File?> _ensureBundledVideoFile() async {
    try {
      final supportDirectory = await getApplicationSupportDirectory();
      final directory = Directory(
        '${supportDirectory.path}${Platform.pathSeparator}backdrops',
      );
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      final target = File('${directory.path}${Platform.pathSeparator}$_fileName');
      if (await target.exists() && await target.length() > 0) {
        return target;
      }
      final data = await rootBundle.load(bundledDefaultWallpaperAssetPath);
      // 先写 .part 再改名：中途被杀不会留下能通过"文件存在"检查的半截视频。
      final staging = File('${target.path}.part');
      await staging.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      await staging.rename(target.path);
      return target;
    } on Object catch (error) {
      if (kDebugMode) {
        devLog('内置壁纸落盘失败,退回打包资产地址: $error');
      }
      return null;
    }
  }

  Future<int> _lengthOrZero(File file) async {
    try {
      return await file.length();
    } on Object {
      return 0;
    }
  }

  Future<void> _cleanUpLegacyFiles() async {
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
