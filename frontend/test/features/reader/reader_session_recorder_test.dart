import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/storage/local_database.dart';
import 'package:omninest/features/reader/application/reader_session_recorder.dart';
import 'package:omninest/features/reader/data/reader_sync_queue.dart';

void main() {
  test('活跃时长不足 10 秒的会话不入队且不触达队列', () {
    // 短会话分支在计算 duration 后直接返回，不会触碰未初始化的
    // ReaderSyncQueue；若误入队会以 StateError 击穿本测试。
    ReaderSessionRecorder.recordSession(
      itemId: 'item-1',
      sessionStart: DateTime.now(),
      activeReading: const Duration(seconds: 5),
    );
  });

  test('活跃时长达标的会话入队失败也不击穿退出路径', () {
    // 测试环境队列未初始化：入队以 Error 失败，recorder 必须吞下并
    // 只留调试日志，保证阅读页 dispose 不因统计副作�用崩溃。
    ReaderSessionRecorder.recordSession(
      itemId: 'item-1',
      sessionStart: DateTime.now().subtract(const Duration(minutes: 30)),
      activeReading: const Duration(minutes: 12),
    );
  });
  test('队列初始化后达标会话写入 reader.session.create，短会话不留行', () async {
    // 漫画/ PDF / 正文三种阅读器退出时都走这里；队列里没有这一行，
    // 统计页的时长与连续天数就永远等不到漫画的阅读记录。
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    ReaderSyncQueue.init(database);

    ReaderSessionRecorder.recordSession(
      itemId: 'item-1',
      sessionStart: DateTime(2026, 10, 15, 10),
      activeReading: const Duration(seconds: 40),
    );
    await Future<void>.delayed(Duration.zero);
    expect(await _sessionTypes(database), hasLength(1));

    ReaderSessionRecorder.recordSession(
      itemId: 'item-1',
      sessionStart: DateTime(2026, 10, 15, 11),
      activeReading: const Duration(seconds: 3),
    );
    await Future<void>.delayed(Duration.zero);
    expect(
      await _sessionTypes(database),
      hasLength(1),
      reason: '三五秒的翻页试探不该算成一次阅读',
    );
  });
}

Future<List<String>> _sessionTypes(LocalDatabase database) async {
  final rows =
      await (database.select(database.syncOperations)..where(
        (table) => table.type.equals(ReaderSyncQueue.opSessionCreate),
      )).get();
  return rows.map((row) => row.type).toList(growable: false);
}
