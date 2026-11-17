import 'package:dio/dio.dart';

/// 非 IO 平台不支持保存到本地路径，Web 端走浏览器原生下载。
Future<void> downloadPhotoFileToPath({
  required Dio dio,
  required String url,
  required int sizeBytes,
  required String destinationPath,
}) {
  throw UnsupportedError('当前平台不支持保存到本地路径');
}
