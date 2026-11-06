import 'package:omninest/features/backdrop/domain/app_backdrop.dart';
import 'package:web/web.dart' as web;

/// Web 平台的内置背景登记：直接引用打包资产地址，不落本机文件。
class AppBackdropBundledAssetInstaller {
  /// 注册内置默认壁纸并返回背景库素材。
  Future<AppBackdropAsset?> install() async {
    final now = DateTime.now();
    return AppBackdropAsset(
      id: bundledDefaultWallpaperId,
      path: _videoUrl,
      title: 'OmniNest',
      mediaType: AppBackdropMediaType.video,
      sourceType: AppBackdropSourceType.bundled,
      fileSize: 0,
      modifiedAt: now,
      createdAt: now,
      updatedAt: now,
      thumbnailPath: bundledDefaultWallpaperPosterAssetPath,
    );
  }

  /// Flutter Web 把 `assets/backdrops/x.mp4` 发布到 `<base href>assets/assets/backdrops/x.mp4`。
  ///
  /// 取 `document.baseURI` 而不是 `Uri.base`：使用路径策略时 `Uri.base` 指向
  /// 当前路由，子路径部署下会把资产解析到错误目录；`<base href>` 才是资产根。
  String get _videoUrl {
    final base = Uri.tryParse(web.document.baseURI) ?? Uri.base;
    return base.resolve('assets/$bundledDefaultWallpaperAssetPath').toString();
  }
}
