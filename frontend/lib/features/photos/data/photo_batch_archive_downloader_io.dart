import 'dart:io';

import 'package:dio/dio.dart';
import 'package:omninest/core/network/resumable_file_downloader.dart';
import 'package:omninest/core/network/resumable_file_ticket.dart';
import 'package:omninest/features/photos/domain/photo_batch_download_ticket.dart';

/// 原生平台将照片 ZIP 下载到半成品路径，校验完成后再原子发布。
Future<void> downloadPhotoBatchArchive({
  required Dio dio,
  required PhotoBatchDownloadTicket ticket,
  required String destinationPath,
}) async {
  final destination = File(destinationPath);
  final partial = File('$destinationPath.omninest.part');
  await downloadResumableFileToPath(
    dio: dio,
    ticket: ResumableFileTicket(
      downloadUrl: ticket.url,
      sizeBytes: ticket.sizeBytes,
      sha256: ticket.sha256,
      errorCodePrefix: 'PHOTO_BATCH_ARCHIVE',
      fileLabel: '照片批量 ZIP',
    ),
    destinationPath: partial.path,
  );
  if (await destination.exists()) {
    await destination.delete();
  }
  await partial.rename(destination.path);
}
