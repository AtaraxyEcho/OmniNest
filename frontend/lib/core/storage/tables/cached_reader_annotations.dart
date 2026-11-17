import 'package:drift/drift.dart';

/// 本地缓存的阅读标注表（离线优先存储）。
///
/// [userId] 是记录归属账号：共享书籍在不同账号下复用同一个 itemId，
/// 没有归属列时换号会读到上一个账号的批注。
@TableIndex(
  name: 'idx_cached_reader_annotations_user_item',
  columns: {#userId, #readerItemId},
)
class CachedReaderAnnotations extends Table {
  TextColumn get id => text()();

  TextColumn get userId => text().withDefault(const Constant(''))();

  TextColumn get readerItemId => text()();

  TextColumn get chapterId => text().nullable()();

  IntColumn get startOffset => integer()();

  IntColumn get endOffset => integer()();

  TextColumn get highlightText => text().nullable()();

  TextColumn get note => text().nullable()();

  TextColumn get color => text().withDefault(const Constant('#FFEB3B'))();

  DateTimeColumn get createdAt => dateTime()();

  /// 服务端乐观锁版本；本地新建或旧库升级后为 null，更新时不带前置条件。
  IntColumn get version => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
