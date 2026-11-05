import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/security/offline_data_lifecycle.dart';
import 'package:omninest/core/security/offline_key_store_base.dart';
import 'package:omninest/core/security/offline_memory_cache.dart';
import 'package:omninest/core/security/offline_text_cipher.dart';
import 'package:omninest/core/storage/local_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 稳定主密钥存储：统计列密钥派生读取次数。
class _CountingKeyStore implements OfflineKeyStore {
  int reads = 0;
  final Map<String, List<int>> _keys = {};

  @override
  Future<void> delete(String userId) async {
    _keys.remove(userId);
  }

  @override
  Future<OfflineMasterKey> readOrCreate(String userId) async {
    reads += 1;
    final key = _keys[userId] ??= List<int>.generate(32, (index) => index + 1);
    return OfflineMasterKey(keyId: 'test', bytes: Uint8List.fromList(key));
  }
}

void main() {
  // 登出闭环同时清偏好快照：没有插件实现时必须用内存桩，否则清理会抛
  // MissingPluginException 并被当作真实失败。
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('平台清理失败时仍清理内存和数据库中的用户数据', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database
        .into(database.syncOperations)
        .insert(
          SyncOperationsCompanion.insert(
            type: 'reader.progress',
            payload: '{"itemId":"book-1"}',
            createdAt: DateTime(2026, 7, 22),
          ),
        );
    OfflineMemoryCache.write(
      userId: 'user-1',
      cacheType: 'reader-book',
      businessId: 'book-1',
      bytes: Uint8List.fromList(const [1, 2, 3]),
    );
    final lifecycle = DatabaseOfflineDataLifecycle(
      delegate: _FailingOfflineDataLifecycle(),
      database: database,
    );

    await expectLater(
      lifecycle.clearUser('user-1'),
      throwsA(isA<FormatException>()),
    );

    expect(await database.select(database.syncOperations).get(), isEmpty);
    expect(
      OfflineMemoryCache.read(
        userId: 'user-1',
        cacheType: 'reader-book',
        businessId: 'book-1',
      ),
      isNull,
    );
  });

  test('清理用户时同步失效派生列密钥缓存', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final keyStore = _CountingKeyStore();
    final cipher = OfflineTextCipher(keyStore: keyStore);
    await cipher.encrypt('user-1', '笔记内容');
    expect(keyStore.reads, 1);

    final lifecycle = DatabaseOfflineDataLifecycle(
      delegate: _NoopOfflineDataLifecycle(),
      database: database,
      textCipher: cipher,
    );
    await lifecycle.clearUser('user-1');

    // 缓存未失效时不会再读主密钥；读取次数增加说明清理流程确实驱逐了派生密钥。
    await cipher.encrypt('user-1', '笔记内容');
    expect(keyStore.reads, 2);
  });

  test('登出同时清掉该账号的偏好快照，保留其他账号与全局键', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('preference.snapshot.user-1.theme', '{"v":1}');
    await preferences.setString('preference.pending.user-1.theme', '{"v":2}');
    await preferences.setInt('preference.pending_delete.user-1.theme', 3);
    await preferences.setString('preference.snapshot.user-2.theme', '{"v":9}');
    await preferences.setString('appearance.theme', 'dark');

    final lifecycle = DatabaseOfflineDataLifecycle(
      delegate: _NoopOfflineDataLifecycle(),
      database: database,
    );
    await lifecycle.clearUser('user-1');

    expect(preferences.getKeys(), {
      'preference.snapshot.user-2.theme',
      'appearance.theme',
    });
  });
}

class _NoopOfflineDataLifecycle implements OfflineDataLifecycle {
  @override
  Future<void> clearUser(String userId) async {}
}

class _FailingOfflineDataLifecycle implements OfflineDataLifecycle {
  @override
  Future<void> clearUser(String userId) {
    throw const FormatException('测试平台清理失败');
  }
}
