import 'package:omninest/features/backdrop/domain/app_backdrop.dart';

/// Web 平台的内置背景注册:直接引用打包资产地址,不落本机文件。
class AppBackdropBundledAssetInstaller {
  static const String assetPath = 'assets/backdrops/default_wallpaper.mp4';

  /// 注册内置动态壁纸并返回背景库素材。
  Future<AppBackdropAsset?> install() async {
    final now = DateTime.now();
    return AppBackdropAsset(
      id: bundledDefaultWallpaperId,
      path: assetPath,
      title: 'OmniNest',
      mediaType: AppBackdropMediaType.video,
      sourceType: AppBackdropSourceType.bundled,
      fileSize: 0,
      modifiedAt: now,
      createdAt: now,
      updatedAt: now,
    );
  }
}
