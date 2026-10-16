import 'package:drift/drift.dart';

/// 本地缓存的阅读书签表
///
/// [userId] 是记录归属账号：共享书籍在不同账号下复用同一个 itemId，
/// 没有归属列时换号会读到上一个账号的书签。
class CachedReaderBookmarks extends Table {
  TextColumn get id => text()();

  TextColumn get userId => text().withDefault(const Constant(''))();

  TextColumn get readerItemId => text()();

  /// 书签所属章节标识。
  ///
  /// `char_offset` 是章内局部偏移，没有归属章节时详情页只能跳回当前进度章。
  TextColumn get chapterId => text().nullable()();

  IntColumn get charOffset => integer().withDefault(const Constant(0))();

  RealColumn get progressPercent => real().withDefault(const Constant(0))();

  TextColumn get note => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
