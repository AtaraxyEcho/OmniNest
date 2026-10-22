import 'package:omninest/core/utils/file_saver.dart';

/// 照片导出结果。
sealed class PhotoExportResult {
  const PhotoExportResult();
}

/// 用户取消选择保存位置。
class PhotoExportCancelled extends PhotoExportResult {
  const PhotoExportCancelled();
}

/// 已写入本地路径（桌面保存对话框目标）。
class PhotoExportSaved extends PhotoExportResult {
  const PhotoExportSaved(this.path);

  final String path;
}

/// 已交给系统分享入口（移动：可存相册或其它应用）。
class PhotoExportShared extends PhotoExportResult {
  const PhotoExportShared();
}

/// 是否使用系统保存对话框选择导出路径（仅桌面）。
bool get photoExportUsesSaveDialog => localFileSaveUsesDialog;

/// 解析照片导出落盘路径。
///
/// 桌面弹出系统保存对话框；移动端写入临时目录，随后由
/// [deliverPhotoExport] 交给系统分享。Web 不走本通道（浏览器下载）。
/// 返回 null 表示用户取消。
Future<String?> resolvePhotoExportPath({required String suggestedName}) {
  return resolveLocalSavePath(
    suggestedName: suggestedName,
    temporaryPrefix: 'omninest_export_',
  );
}

/// 下载完成后的交付动作。
///
/// 移动端把文件交给系统分享（用户可保存到相册/文件）；桌面文件已写入
/// 对话框所选路径，无需额外动作。
Future<PhotoExportResult> deliverPhotoExport({
  required String path,
  required String fileName,
}) async {
  final result = await deliverLocalFile(path: path, fileName: fileName);
  return switch (result) {
    LocalFileSaveShared() => const PhotoExportShared(),
    _ => PhotoExportSaved(path),
  };
}
