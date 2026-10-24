import 'package:drift/drift.dart';

/// 本地缓存的媒体播放进度表。
///
/// 主键包含账号归属：同设备切换账号后，共享曲目会复用同一个 mediaId，
/// 不隔离就会读到上一个账号的播放位置，且任一账号退出会清掉其他账号的离线进度。
class CachedMediaProgress extends Table {
  TextColumn get userId => text().withDefault(const Constant(''))();

  TextColumn get mediaId => text()();

  TextColumn get mediaType => text()();

  RealColumn get progressPercent => real()();

  IntColumn get positionSeconds => integer()();

  IntColumn get durationSeconds => integer()();

  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {userId, mediaId};
}
