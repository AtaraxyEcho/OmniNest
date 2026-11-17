import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/domain/reader_progress_backup_key.dart';

/// 摘要：Web 崩溃备份的 localStorage 键必须按账号分。
///
/// 共享空间的书在不同账号下复用同一个 itemId，键名不带账号时账号 A 的备份会被账号 B
/// 当作"本机唯一进度"回填进 B 的 SQLite（B 此时没有本地行，`preferCrashBackup` 判备份赢）。
void main() {
  test('同一本书在不同账号下取不同键', () {
    final first = readerProgressBackupKey(userId: 'user-a', itemId: 'book-1');
    final second = readerProgressBackupKey(userId: 'user-b', itemId: 'book-1');
    final same = readerProgressBackupKey(userId: 'user-a', itemId: 'book-2');

    expect(first, isNot(second));
    expect(first, 'omninest_progress_user-a_book-1');
    expect(same, 'omninest_progress_user-a_book-2');
  });

  test('未绑定账号时退回设备级键名', () {
    expect(
      readerProgressBackupKey(userId: null, itemId: 'book-1'),
      'omninest_progress_book-1',
    );
    expect(
      readerProgressBackupKey(userId: '   ', itemId: 'book-1'),
      'omninest_progress_book-1',
      reason: '空白账号名等未登录处理，不能造出带空格的第三种键',
    );
  });

  test('账号 id 两侧空白不参与键名', () {
    expect(
      readerProgressBackupKey(userId: ' user-a ', itemId: 'book-1'),
      readerProgressBackupKey(userId: 'user-a', itemId: 'book-1'),
    );
  });
}
