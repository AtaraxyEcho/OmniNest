import 'package:omninest/features/backdrop/domain/app_backdrop.dart';

/// Web 平台的内置背景登记:直接引用打包资产地址,不落本机文件;
/// Web 归入桌面档,使用桌面端内置默认图。
class AppBackdropBundledAssetInstaller {
  /// 注册内置默认壁纸并返回背景库素材。
  Future<AppBackdropAsset?> install(AppBackdropSelectionTarget target) async {
    final now = DateTime.now();
    return AppBackdropAsset(
      id: bundledDefaultWallpaperId,
      path: bundledWallpaperAssetPathFor(target),
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
