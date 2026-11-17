import 'package:dio/dio.dart';
import 'package:omninest/core/network/resumable_file_downloader_stub.dart'
    if (dart.library.io) 'package:omninest/core/network/resumable_file_downloader_io.dart'
    as platform;
import 'package:omninest/core/network/resumable_file_ticket.dart';

/// 使用 HTTP Range 将文件续传到指定路径并校验大小和摘要。
Future<void> downloadResumableFileToPath({
  required Dio dio,
  required ResumableFileTicket ticket,
  required String destinationPath,
}) {
  return platform.downloadResumableFileToPath(
    dio: dio,
    ticket: ticket,
    destinationPath: destinationPath,
  );
}
