import 'package:omninest/core/storage/local_database.dart';
import 'package:omninest/features/reader/data/reader_image_repository_base.dart';
import 'package:omninest/features/reader/data/reader_image_repository_stub.dart'
    if (dart.library.ffi) 'package:omninest/features/reader/data/reader_image_repository_io.dart'
    if (dart.library.js_interop) 'package:omninest/features/reader/data/reader_image_repository_web.dart'
    as implementation;

/// 创建当前平台的阅读图片缓存仓库。
ReaderImageRepository createReaderImageRepository({
  required LocalDatabase database,
  required String? userId,
}) {
  if (userId == null || userId.isEmpty) {
    return const DisabledReaderImageRepository();
  }
  return implementation.createReaderImageRepository(
    database: database,
    userId: userId,
  );
}
