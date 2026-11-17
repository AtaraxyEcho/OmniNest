import 'package:drift/drift.dart';

/// 本地缓存的阅读笔记表（离线优先存储）。
///
/// [userId] 是记录归属账号：共享书籍在不同账号下复用同一个 itemId，
/// 没有归属列时换号会读到上一个账号的笔记。
@TableIndex(
  name: 'idx_cached_reader_notes_user_item',
  columns: {#userId, #readerItemId},
)
class CachedReaderNotes extends Table {
  TextColumn get id => text()();

  TextColumn get userId => text().withDefault(const Constant(''))();

  TextColumn get readerItemId => text()();

  IntColumn get charOffset => integer().nullable()();

  TextColumn get title => text().nullable()();

  TextColumn get content => text()();

  DateTimeColumn get createdAt => dateTime()();

  /// 服务端乐观锁版本；本地新建或旧库升级后为 null，更新时不带前置条件。
  IntColumn get version => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
