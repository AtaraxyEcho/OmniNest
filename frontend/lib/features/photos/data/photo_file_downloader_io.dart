import 'dart:io';

import 'package:dio/dio.dart';
import 'package:omninest/core/network/resumable_file_downloader.dart';
import 'package:omninest/core/network/resumable_file_ticket.dart';

/// 原生平台将照片原片续传到半成品路径，校验完成后再原子发布。
Future<void> downloadPhotoFileToPath({
  required Dio dio,
  required String url,
  required int sizeBytes,
  required String destinationPath,
}) async {
  final destination = File(destinationPath);
  final partial = File('$destinationPath.omninest.part');
  await downloadResumableFileToPath(
    dio: dio,
    ticket: ResumableFileTicket(
      downloadUrl: url,
      sizeBytes: sizeBytes,
      errorCodePrefix: 'PHOTO_FILE',
      fileLabel: '照片原片',
    ),
    destinationPath: partial.path,
  );
  if (await destination.exists()) {
    await destination.delete();
  }
  await partial.rename(destination.path);
}
