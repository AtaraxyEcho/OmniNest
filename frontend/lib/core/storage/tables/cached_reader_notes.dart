import 'package:drift/drift.dart';

/// 本地缓存的阅读笔记表（离线优先存储）。
///
/// [userId] 是记录归属账号：共享书籍在不同账号下复用同一个 itemId，
/// 没有归属列时换号会读到上一个账号的笔记。
class CachedReaderNotes extends Table {
  TextColumn get id => text()();

  TextColumn get userId => text().withDefault(const Constant(''))();

  TextColumn get readerItemId => text()();

  IntColumn get charOffset => integer().nullable()();

  TextColumn get title => text().nullable()();

  TextColumn get content => text()();

  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
