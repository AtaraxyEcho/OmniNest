import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart';
import 'package:omninest/core/network/resumable_file_downloader.dart';
import 'package:omninest/core/network/resumable_file_ticket.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/platform/platform_capabilities.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 本地保存结果。
sealed class LocalFileSaveResult {
  const LocalFileSaveResult();
}

/// 用户取消了保存位置选择。
class LocalFileSaveCancelled extends LocalFileSaveResult {
  const LocalFileSaveCancelled();
}

/// 已写入本地路径（桌面保存对话框目标）。
class LocalFileSaveSaved extends LocalFileSaveResult {
  const LocalFileSaveSaved(this.path);

  final String path;
}

/// 已交给系统分享入口（移动端可另存到相册或其它应用）。
class LocalFileSaveShared extends LocalFileSaveResult {
  const LocalFileSaveShared();
}

/// 是否使用系统保存对话框选择落盘路径（仅桌面）。
bool get localFileSaveUsesDialog =>
    PlatformCapabilities.current().supportsFileSystemSaveDialog;

/// 解析本地落盘路径。
///
/// 桌面弹出系统保存对话框；移动端写入临时目录，随后由 [deliverLocalFile]
/// 交给系统分享。返回 null 表示用户取消。
Future<String?> resolveLocalSavePath({
  required String suggestedName,
  String temporaryPrefix = 'omninest_download_',
}) async {
  if (isMobilePlatform) {
    final dir = await getTemporaryDirectory();
    final safeName = suggestedName.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
    return '${dir.path}/$temporaryPrefix$safeName';
  }
  final location = await getSaveLocation(suggestedName: suggestedName);
  return location?.path;
}

/// 把签名下载地址流式保存到本地。
///
/// 与照片导出共用同一套可续传下载与交付路径；签名地址不需要鉴权头，
/// 因此使用独立 Dio，避免把 API 拦截器带到对象存储域名。
Future<LocalFileSaveResult> saveDownloadUrlToLocalFile({
  required String url,
  required String fileName,
  required int sizeBytes,
  String? sha256,
  String errorCodePrefix = 'FILE_DOWNLOAD',
  String temporaryPrefix = 'omninest_download_',
  Dio? dio,
}) async {
  final targetPath = await resolveLocalSavePath(
    suggestedName: fileName,
    temporaryPrefix: temporaryPrefix,
  );
  if (targetPath == null) {
    return const LocalFileSaveCancelled();
  }
  await downloadResumableFileToPath(
    dio: dio ?? _downloadDio,
    ticket: ResumableFileTicket(
      downloadUrl: url,
      sizeBytes: sizeBytes,
      sha256: sha256,
      errorCodePrefix: errorCodePrefix,
      fileLabel: fileName,
    ),
    destinationPath: targetPath,
  );
  return deliverLocalFile(path: targetPath, fileName: fileName);
}

/// 下载完成后的交付动作：桌面已落盘；移动端交给系统分享。
Future<LocalFileSaveResult> deliverLocalFile({
  required String path,
  required String fileName,
}) async {
  if (!isMobilePlatform) {
    return LocalFileSaveSaved(path);
  }
  try {
    await SharePlus.instance.share(
      ShareParams(files: [XFile(path)], fileNameOverrides: [fileName]),
    );
    return const LocalFileSaveShared();
  } on Object {
    // 分享面板不可用时文件仍在临时目录，按已保存反馈。
    return LocalFileSaveSaved(path);
  }
}

final Dio _downloadDio = Dio();
