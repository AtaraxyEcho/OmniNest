import 'package:file_selector/file_selector.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/platform/platform_capabilities.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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
bool get photoExportUsesSaveDialog =>
    PlatformCapabilities.current().supportsFileSystemSaveDialog;

/// 解析照片导出落盘路径。
///
/// 桌面弹出系统保存对话框；移动端写入临时目录，随后由
/// [deliverPhotoExport] 交给系统分享。Web 不走本通道（浏览器下载）。
/// 返回 null 表示用户取消。
Future<String?> resolvePhotoExportPath({required String suggestedName}) async {
  if (isMobilePlatform) {
    final dir = await getTemporaryDirectory();
    final safeName = suggestedName.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
    return '${dir.path}/omninest_export_$safeName';
  }
  final location = await getSaveLocation(suggestedName: suggestedName);
  return location?.path;
}

/// 下载完成后的交付动作。
///
/// 移动端把文件交给系统分享（用户可保存到相册/文件）；桌面文件已写入
/// 对话框所选路径，无需额外动作。
Future<PhotoExportResult> deliverPhotoExport({
  required String path,
  required String fileName,
}) async {
  if (!isMobilePlatform) {
    return PhotoExportSaved(path);
  }
  try {
    await SharePlus.instance.share(
      ShareParams(files: [XFile(path)], fileNameOverrides: [fileName]),
    );
    return const PhotoExportShared();
  } on Object {
    // 分享面板不可用时仍保留临时文件，按已保存反馈。
    return PhotoExportSaved(path);
  }
}
