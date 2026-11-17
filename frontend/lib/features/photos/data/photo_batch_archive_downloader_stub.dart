import 'package:dio/dio.dart';
import 'package:omninest/features/photos/domain/photo_batch_download_ticket.dart';

/// 非文件系统平台不支持照片 ZIP 下载到本地路径。
Future<void> downloadPhotoBatchArchive({
  required Dio dio,
  required PhotoBatchDownloadTicket ticket,
  required String destinationPath,
}) {
  throw UnsupportedError('当前平台不支持照片 ZIP 下载到本地路径');
}
