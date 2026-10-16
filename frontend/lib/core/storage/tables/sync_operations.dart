import 'package:drift/drift.dart';

/// 离线同步操作队列表
///
/// [userId] 是操作归属账号。reader 操作按它隔离：共享书籍在不同账号下复用
/// 同一个 itemId，换号后重放上一个账号积压的离线操作会把位置写到新账号名下。
/// 其他模块的队列行不写该列，也不按它过滤。
class SyncOperations extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get userId => text().withDefault(const Constant(''))();

  TextColumn get type => text()();

  TextColumn get payload => text()();

  TextColumn get status => text().withDefault(const Constant('pending'))();

  IntColumn get retryCount => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get syncedAt => dateTime().nullable()();
}
