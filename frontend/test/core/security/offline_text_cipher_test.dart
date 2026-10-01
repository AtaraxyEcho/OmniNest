import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/security/offline_key_store_base.dart';
import 'package:omninest/core/security/offline_text_cipher.dart';

/// 内存密钥存储，密钥按用户保存于测试进程内。
class _InMemoryKeyStore implements OfflineKeyStore {
  final Map<String, List<int>> _keys = {};

  @override
  Future<void> delete(String userId) async {
    _keys.remove(userId);
  }

  @override
  Future<OfflineMasterKey> readOrCreate(String userId) async {
    final existing = _keys[userId];
    if (existing != null) {
      return OfflineMasterKey(
        keyId: 'test',
        bytes: Uint8List.fromList(existing),
      );
    }
    final generated = List<int>.generate(32, (index) => index + userId.length);
    _keys[userId] = generated;
    return OfflineMasterKey(
      keyId: 'test',
      bytes: Uint8List.fromList(generated),
    );
  }
}

void main() {
  test('加密后可解密还原，密文带前缀且两次加密结果不同', () async {
    final cipher = OfflineTextCipher(keyStore: _InMemoryKeyStore());

    final encrypted = await cipher.encrypt('user-1', '章节正文内容');
    final encryptedAgain = await cipher.encrypt('user-1', '章节正文内容');

    expect(encrypted.startsWith('enc:v1:'), isTrue);
    expect(encrypted, isNot(equals(encryptedAgain)));
    expect(await cipher.decrypt('user-1', encrypted), equals('章节正文内容'));
  });

  test('无前缀的历史明文按明文返回', () async {
    final cipher = OfflineTextCipher(keyStore: _InMemoryKeyStore());

    expect(await cipher.decrypt('user-1', '旧版明文章节'), equals('旧版明文章节'));
    expect(await cipher.decrypt('user-1', ''), equals(''));
  });

  test('不同用户的列密钥互相隔离', () async {
    final cipher = OfflineTextCipher(keyStore: _InMemoryKeyStore());

    final encrypted = await cipher.encrypt('alice', '跨用户不可读');

    expect(await cipher.decrypt('bob', encrypted), equals(''));
  });

  test('密文被篡改时按缓存未命中处理返回空串', () async {
    final cipher = OfflineTextCipher(keyStore: _InMemoryKeyStore());

    final encrypted = await cipher.encrypt('user-1', '待篡改内容');
    final tampered = '${encrypted.substring(0, encrypted.length - 4)}AAAA';

    expect(await cipher.decrypt('user-1', tampered), equals(''));
  });

  test('空文本保持空串语义', () async {
    final cipher = OfflineTextCipher(keyStore: _InMemoryKeyStore());

    expect(await cipher.encrypt('user-1', ''), equals(''));
  });
}
