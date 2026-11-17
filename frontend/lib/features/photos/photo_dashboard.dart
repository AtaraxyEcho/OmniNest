/// 照片模块提供给跨 Feature 仪表盘的只读契约。
library;

// 控制器库整份导出：回收站/收藏等动作是扩展方法，`show` 白名单导不出。
export 'package:omninest/features/photos/application/photo_controller.dart';
export 'package:omninest/features/photos/application/photo_repository_providers.dart';
export 'package:omninest/features/photos/application/photo_center_models.dart'
    show FrameView, PhotoCenterState;
export 'package:omninest/features/photos/platform/photo_save_channel.dart'
    show
        PhotoExportCancelled,
        PhotoExportResult,
        PhotoExportSaved,
        PhotoExportShared,
        deliverPhotoExport,
        resolvePhotoExportPath;
export 'package:omninest/features/photos/domain/photo.dart'
    show PhotoDashboard, PhotoItem, PhotoPage;
export 'package:omninest/features/photos/domain/photo_album.dart'
    show PhotoAlbum;
export 'package:omninest/features/photos/domain/photo_group.dart'
    show PhotoGroup;
