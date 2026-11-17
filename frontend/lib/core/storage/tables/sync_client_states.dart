import 'package:drift/drift.dart';

/// 服务端和用户维度的同步游标状态表。
class SyncClientStates extends Table {
  TextColumn get serverKey => text()();

  TextColumn get userId => text()();

  IntColumn get cursor => integer().withDefault(const Constant(0))();

  IntColumn get schemaVersion => integer().withDefault(const Constant(1))();

  DateTimeColumn get lastSyncAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {serverKey, userId};
}
