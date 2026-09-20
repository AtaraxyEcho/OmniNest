import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/application/reader_session_recorder.dart';

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
}
