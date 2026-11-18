import 'package:omninest/features/backdrop/domain/app_backdrop.dart';

/// IO 平台登记随应用打包的静态默认壁纸。
class AppBackdropBundledAssetInstaller {
  /// 登记内置默认壁纸并返回背景库素材。
  Future<AppBackdropAsset?> install() async {
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
      thumbnailPath: bundledDefaultWallpaperPosterAssetPath,
    );
  }
}
