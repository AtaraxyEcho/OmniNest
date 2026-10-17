import 'package:drift/drift.dart';

import 'package:omninest/core/storage/local_database.dart';

/// 离线操作同步队列。
/// 网络恢复后按顺序重放待处理操作。
///
/// [userId] 是操作归属账号：`sync_operations` 是各业务域共用的表，reader 侧已按账号
/// 隔离，这里也必须落同一个口径——否则同设备换号后，上一个账号积压的播放位置会被
/// 用当前账号的身份重放出去，当前账号的退登清理也说不清清了谁的数据。未登录时按
/// 写入用的 `''` 精确匹配，不放行成全表匹配。
class SyncQueue {
  /// 创建同步队列实例
  SyncQueue(this._db, {String? userId}) : _userId = userId ?? '';

  final LocalDatabase _db;
  final String _userId;

  Expression<bool> _owned(GeneratedColumn<String> column) =>
      column.equals(_userId);

  /// 入队一条离线操作。
  Future<int> enqueue({required String type, required String payload}) {
    return _db
        .into(_db.syncOperations)
        .insert(
          SyncOperationsCompanion.insert(
            userId: Value(_userId),
            type: type,
            payload: payload,
            createdAt: DateTime.now(),
          ),
        );
  }

  /// 合并同一类型尚未同步的操作，只保留最新负载。
  Future<int> enqueueLatest({required String type, required String payload}) {
    return _db.transaction(() async {
      await (_db.delete(_db.syncOperations)..where(
        (table) =>
            _owned(table.userId) &
            table.type.equals(type) &
            (table.status.equals('pending') | table.status.equals('failed')),
      )).go();
      return enqueue(type: type, payload: payload);
    });
  }

  /// 判断指定操作类型是否存在待同步记录。
  Future<bool> hasPending(String type) async {
    final row =
        await (_db.select(_db.syncOperations)..where(
          (table) =>
              _owned(table.userId) &
              table.type.equals(type) &
              (table.status.equals('pending') | table.status.equals('failed')),
        )).getSingleOrNull();
    return row != null;
  }

  /// 取出指定数量的待处理操作。
  Future<List<SyncOperation>> dequeue({int limit = 20}) {
    return (_db.select(_db.syncOperations)
          ..where(
            (t) =>
                _owned(t.userId) &
                t.status.equals('pending') &
                t.type.like('reader.%').not(),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
          ..limit(limit))
        .get();
  }

  /// 标记操作已完成。
  Future<void> markCompleted(int id) {
    return (_db.update(_db.syncOperations)
      ..where((t) => t.id.equals(id) & _owned(t.userId))).write(
      SyncOperationsCompanion(
        status: const Value('completed'),
        syncedAt: Value(DateTime.now()),
      ),
    );
  }

  /// 标记操作失败，递增重试次数。
  Future<void> markFailed(int id) async {
    final op =
        await (_db.select(_db.syncOperations)
          ..where((t) => t.id.equals(id) & _owned(t.userId))).getSingle();
    await (_db.update(_db.syncOperations)
      ..where((t) => t.id.equals(id) & _owned(t.userId))).write(
      SyncOperationsCompanion(
        status: const Value('failed'),
        retryCount: Value(op.retryCount + 1),
      ),
    );
  }

  /// 重试失败的操作（重置为 pending）。
  Future<void> retryFailed({int maxRetries = 3}) {
    return (_db.update(_db.syncOperations)..where(
      (t) =>
          _owned(t.userId) &
          t.status.equals('failed') &
          t.retryCount.isSmallerThanValue(maxRetries) &
          t.type.like('reader.%').not(),
    )).write(const SyncOperationsCompanion(status: Value('pending')));
  }

  /// 获取待处理操作数量。
  Future<int> pendingCount() async {
    final count = _db.syncOperations.id.count();
    final query =
        _db.selectOnly(_db.syncOperations)
          ..addColumns([count])
          ..where(
            _owned(_db.syncOperations.userId) &
                _db.syncOperations.status.equals('pending'),
          );
    final result = await query.getSingle();
    return result.read(count) ?? 0;
  }

  /// 清除已完成的操作。
  Future<int> clearCompleted() {
    return (_db.delete(_db.syncOperations)
      ..where((t) => _owned(t.userId) & t.status.equals('completed'))).go();
  }
}
