import 'package:dio/dio.dart';
import 'package:omninest/features/photos/data/photo_batch_archive_downloader_stub.dart'
    if (dart.library.io) 'package:omninest/features/photos/data/photo_batch_archive_downloader_io.dart'
    as platform;
import 'package:omninest/features/photos/domain/photo_batch_download_ticket.dart';

/// 将照片批量 ZIP 续传到用户选择的本地路径。
Future<void> downloadPhotoBatchArchive({
  required Dio dio,
  required PhotoBatchDownloadTicket ticket,
  required String destinationPath,
}) {
  return platform.downloadPhotoBatchArchive(
    dio: dio,
    ticket: ticket,
    destinationPath: destinationPath,
  );
}
