import 'package:drift/drift.dart';

/// 阅读图片加密文件索引表。
///
/// 图片正文保存在用户隔离的加密文件中，SQLite 仅保存定位和缓存治理所需元数据。
class CachedReaderImages extends Table {
  /// 缓存所属用户 ID。
  TextColumn get userId => text()();

  /// 阅读条目 ID。
  TextColumn get itemId => text()();

  /// 图片在原始阅读文件中的路径。
  TextColumn get imagePath => text()();

  /// 图片 MIME 类型。
  TextColumn get mimeType => text().withDefault(const Constant('image/png'))();

  /// 加密文件的稳定存储键。
  TextColumn get storageKey => text()();

  /// 图片明文字节数。
  IntColumn get sizeBytes => integer()();

  /// 加密信封版本。
  IntColumn get encryptionVersion => integer().withDefault(const Constant(2))();

  /// 缓存创建时间。
  DateTimeColumn get cachedAt => dateTime()();

  /// 最近访问时间。
  DateTimeColumn get lastAccessedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {userId, itemId, imagePath};
}
