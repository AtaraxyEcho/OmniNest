import 'package:drift/drift.dart';

/// 已摄取同步事件的限时去重记录表。
/// 去重查询固定按 (服务端, 账号, 处理时间) 过滤并清理过期行，缺索引时每次
/// 摄取事件都要全表扫描。
@TableIndex(
  name: 'idx_sync_processed_events_server_user_time',
  columns: {#serverKey, #userId, #processedAt},
)
class SyncProcessedEvents extends Table {
  TextColumn get serverKey => text()();

  TextColumn get userId => text()();

  TextColumn get eventId => text()();

  IntColumn get sequenceNo => integer()();

  DateTimeColumn get processedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {serverKey, userId, eventId};
}
