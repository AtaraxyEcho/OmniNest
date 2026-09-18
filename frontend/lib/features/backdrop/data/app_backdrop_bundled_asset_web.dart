import 'package:omninest/features/backdrop/domain/app_backdrop.dart';

/// Web 平台的内置背景登记:直接引用打包资产地址,不落本机文件。
class AppBackdropBundledAssetInstaller {
  /// 注册内置默认壁纸并返回背景库素材。
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
    );
  }
}
