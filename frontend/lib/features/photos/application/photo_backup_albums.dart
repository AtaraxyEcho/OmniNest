import 'package:photo_manager/photo_manager.dart';

/// 相册选择项（备份自选范围 UI 用）。
class PhotoBackupAlbumOption {
  const PhotoBackupAlbumOption({
    required this.id,
    required this.name,
    required this.assetCount,
  });

  final String id;
  final String name;
  final int assetCount;
}

/// 相册枚举函数：默认走 photo_manager；测试通过覆盖 [photoBackupAlbumLoader]
/// 注入假数据，避免依赖平台通道。
typedef PhotoBackupAlbumLoader =
    Future<List<PhotoBackupAlbumOption>> Function();

Future<List<PhotoBackupAlbumOption>> loadPhotoBackupAlbums() async {
  final PermissionState permission =
      await PhotoManager.requestPermissionExtend();
  if (!permission.isAuth) {
    return const [];
  }
  final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
    type: RequestType.image,
    hasAll: false,
  );
  final options = <PhotoBackupAlbumOption>[];
  for (final album in albums) {
    options.add(
      PhotoBackupAlbumOption(
        id: album.id,
        name: album.name,
        assetCount: await album.assetCountAsync,
      ),
    );
  }
  return options;
}

/// 可注入的相册加载入口（生产为 [loadPhotoBackupAlbums]，测试覆写）。
PhotoBackupAlbumLoader photoBackupAlbumLoader = loadPhotoBackupAlbums;
