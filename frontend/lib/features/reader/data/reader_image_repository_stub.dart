import 'package:omninest/core/storage/local_database.dart';
import 'package:omninest/features/reader/data/reader_image_repository_base.dart';

/// 创建不支持持久化文件的平台占位实现。
ReaderImageRepository createReaderImageRepository({
  required LocalDatabase database,
  required String userId,
}) {
  return const DisabledReaderImageRepository();
}
