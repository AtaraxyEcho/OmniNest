import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 离线密钥与同步队列的架构契约。
///
/// 这些不变量都对应过一次真实数据丢失或跨账号串写：密钥实例分叉导致登出没有销毁
/// 真正的密钥、跨标签页误删他人队列、并发 flush 造成 localId 双份、换号途中把操作
/// 写进新账号。改回旧写法时，本测试必须先失败。
void main() {
  String read(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      fail('缺少文件：$path');
    }
    return file.readAsStringSync();
  }

  test('Web 与 Stub 密钥存储必须是共享单例并在删除时清零', () {
    for (final path in <String>[
      'lib/core/security/offline_key_store_web.dart',
      'lib/core/security/offline_key_store_stub.dart',
    ]) {
      final source = read(path);
      final sharesSingleton =
          source.contains('_sharedMemoryKeyStore') ||
          source.contains('web.createOfflineKeyStore()');
      expect(sharesSingleton, isTrue, reason: '$path 每次新建实例会让登出清理销毁错误的对象');
    }
    final web = read('lib/core/security/offline_key_store_web.dart');
    expect(web, contains('fillRange(0, bytes.length, 0)'));
  });

  test('同步队列必须保留单飞脏循环与账号快照', () {
    final source =
        read('lib/features/reader/data/reader_sync_queue.dart') +
        read('lib/features/reader/data/reader_sync_queue_flush.dart');
    expect(source, contains('_activeFlush'));
    expect(source, contains('_needsAnotherPass'));
    expect(source, contains('sessionUserId'));
    expect(source, contains('on Object'));
    expect(source, contains('_encryptedOperationTypes'));
    expect(
      source,
      isNot(contains('if (_syncing ||')),
      reason: '并发 flush 必须等待在途轮次，而不是直接短路',
    );
  });

  test('载荷解码不得把密文当明文解析', () {
    final source = read(
      'lib/features/reader/data/reader_sync_queue_payload.dart',
    );
    expect(source, contains('OfflineTextCipher.isEncryptedValue'));
    expect(source, contains('return null;'));
  });

  test('笔记与章节标题必须走列加密', () {
    final source = read('lib/features/reader/data/reader_local_storage.dart');
    expect(source, contains('_encipherNullable(note.title)'));
    expect(source, contains('_encipherNullable(title)'));
    expect(source, contains('阅读器本地存储缺少登录用户绑定'), reason: '已配置加密器时缺少账号必须拒绝明文落库');
  });

  test('同步队列表必须有复合索引', () {
    final table = read('lib/core/storage/tables/sync_operations.dart');
    expect(table, contains('idx_sync_ops_user_status_type_created'));
    final database = read('lib/core/storage/local_database.dart');
    expect(database, contains('idx_sync_ops_user_status_type_created'));
  });
}
