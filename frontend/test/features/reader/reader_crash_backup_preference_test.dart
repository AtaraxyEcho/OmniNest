import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_progress_helper.dart';

/// 摘要：崩溃备份与本地行的新旧判定必须按时刻，不能按字符串。
///
/// 备份自 2026-10-09 起以 UTC 写出，但历史备份与 drift 读回的本地时间串仍会
/// 相遇；同一时刻的两种写法（不同偏移量）在字典序下会被误判为一新一旧，
/// 误判方向决定"恢复时用哪份进度"，判错就把用户回退到更早的位置。
void main() {
  group('preferCrashBackup', () {
    test('同一时刻的不同时区写法不算更新', () {
      expect(
        preferCrashBackup(
          backupSavedAt: '2026-10-08T01:02:03.000Z',
          localUpdatedAt: '2026-10-07T20:02:03.000-05:00',
        ),
        isFalse,
        reason: '两者是同一时刻（20:02-05:00 == 01:02Z），但字典序会把备份判成更新',
      );
    });

    test('备份确实更晚时采信备份', () {
      expect(
        preferCrashBackup(
          backupSavedAt: '2026-10-08T01:02:04.000Z',
          localUpdatedAt: '2026-10-08T01:02:03.000Z',
        ),
        isTrue,
      );
    });

    test('备份更早时保留本地行', () {
      expect(
        preferCrashBackup(
          backupSavedAt: '2026-10-08T01:02:02.000Z',
          localUpdatedAt: '2026-10-08T01:02:03.000Z',
        ),
        isFalse,
      );
    });

    test('备份时间戳解析不出来时不采信', () {
      expect(
        preferCrashBackup(backupSavedAt: '', localUpdatedAt: 'anything'),
        isFalse,
      );
      expect(
        preferCrashBackup(
          backupSavedAt: 'not-a-timestamp',
          localUpdatedAt: '2026-10-08T01:02:03.000Z',
        ),
        isFalse,
      );
    });

    test('本地行没有可用时间戳时备份胜出', () {
      expect(
        preferCrashBackup(
          backupSavedAt: '2026-10-08T01:02:03.000Z',
          localUpdatedAt: '',
        ),
        isTrue,
      );
      expect(
        preferCrashBackup(backupSavedAt: null, localUpdatedAt: null),
        isFalse,
      );
    });
  });
}
