import 'package:drift/drift.dart';

/// 本地缓存的阅读进度表（V3：按章节存储进度）。
///
/// 主键 (userId, itemId, chapterId) 支持同时保存多个章节的进度，
/// 切换章节时不会覆盖之前章节的进度。共享空间的书籍在不同账号下复用同一个
/// itemId，因此归属必须进主键：否则同设备换号会读到上一个账号的位置，
/// 新账号的一次写入还会顶掉旧账号尚未补传的进度。
class CachedReaderProgress extends Table {
  TextColumn get userId => text().withDefault(const Constant(''))();

  TextColumn get itemId => text()();

  TextColumn get chapterId => text().withDefault(const Constant(''))();

  IntColumn get charOffset => integer().withDefault(const Constant(0))();

  RealColumn get chapterProgress => real().withDefault(const Constant(0))();

  /// 全书进度（0-1）；null 表示落盘时清单口径尚不可用。
  ///
  /// 缺这一列时停在非首章章首（charOffset 与章内比例都是 0）的本地快照
  /// 会被判成"没有可读进度"，对账时被服务端旧章位置覆盖。
  RealColumn get bookProgress => real().nullable()();

  TextColumn get mode => text().withDefault(const Constant('scroll'))();

  TextColumn get pageId => text().nullable()();

  IntColumn get pageIndex => integer().nullable()();

  TextColumn get pageFingerprint => text().nullable()();

  TextColumn get sourceId => text().nullable()();

  IntColumn get sourcePageIndex => integer().nullable()();

  TextColumn get catalogKey => text().nullable()();

  IntColumn get manifestVersion => integer().nullable()();

  RealColumn get intraPageOffset => real().nullable()();

  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {userId, itemId, chapterId};
}
