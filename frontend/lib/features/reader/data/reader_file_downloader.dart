import 'package:dio/dio.dart';
import 'package:omninest/core/network/resumable_file_downloader.dart';
import 'package:omninest/core/network/resumable_file_ticket.dart';
import 'package:omninest/features/reader/domain/reader_file_ticket.dart';

/// 将阅读源文件下载到指定路径。
Future<void> downloadReaderFileToPath({
  required Dio dio,
  required ReaderFileTicket ticket,
  required String destinationPath,
}) {
  return downloadResumableFileToPath(
    dio: dio,
    ticket: ResumableFileTicket(
      downloadUrl: ticket.downloadUrl,
      sizeBytes: ticket.sizeBytes,
      sha256: ticket.sha256,
      errorCodePrefix: 'READER_FILE',
      fileLabel: '阅读文件',
    ),
    destinationPath: destinationPath,
  );
}
