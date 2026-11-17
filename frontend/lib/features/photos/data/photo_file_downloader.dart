import 'package:dio/dio.dart';
import 'package:omninest/features/photos/data/photo_file_downloader_stub.dart'
    if (dart.library.io) 'package:omninest/features/photos/data/photo_file_downloader_io.dart'
    as platform;

/// 将单张照片原片续传到用户选择的本地路径，完成后原子发布。
Future<void> downloadPhotoFileToPath({
  required Dio dio,
  required String url,
  required int sizeBytes,
  required String destinationPath,
}) {
  return platform.downloadPhotoFileToPath(
    dio: dio,
    url: url,
    sizeBytes: sizeBytes,
    destinationPath: destinationPath,
  );
}
