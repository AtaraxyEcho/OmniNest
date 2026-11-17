import 'package:dio/dio.dart';
import 'package:omninest/core/network/resumable_file_ticket.dart';

/// 非文件系统平台不支持下载到本地路径。
Future<void> downloadResumableFileToPath({
  required Dio dio,
  required ResumableFileTicket ticket,
  required String destinationPath,
}) {
  throw UnsupportedError('当前平台不支持下载到本地路径');
}
