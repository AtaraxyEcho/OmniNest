import 'package:drift/drift.dart';

/// 等待业务模块确认刷新的同步失效记录表。
class SyncPendingInvalidations extends Table {
  TextColumn get serverKey => text()();

  TextColumn get userId => text()();

  TextColumn get invalidationKey => text()();

  TextColumn get scope => text()();

  TextColumn get resourceType => text()();

  TextColumn get resourceId => text().nullable()();

  IntColumn get revision => integer().withDefault(const Constant(1))();

  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {serverKey, userId, invalidationKey};
}
