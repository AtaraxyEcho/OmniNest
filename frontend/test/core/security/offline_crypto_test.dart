import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/security/offline_crypto.dart';

void main() {
  const crypto = OfflineCrypto();

  test('generateKey 返回 32 字节随机密钥', () {
    final first = crypto.generateKey();
    final second = crypto.generateKey();

    expect(first, hasLength(32));
    expect(second, hasLength(32));
    expect(first, isNot(equals(second)));
  });

  test('AES-GCM v2 信封可往返 Unicode 文本', () async {
    final key = crypto.generateKey();
    final encrypted = await crypto.encrypt(
      '你好 OmniNest',
      key,
      keyId: 'user-key-v1',
      aad: utf8.encode('user-1:reader:item-1'),
    );

    final decrypted = await crypto.decryptEnvelope(
      encrypted,
      key,
      aad: utf8.encode('user-1:reader:item-1'),
    );

    expect(crypto.isVersion2(encrypted), isTrue);
    expect(decrypted.plaintext, '你好 OmniNest');
    expect(decrypted.keyId, 'user-key-v1');
    expect(decrypted.needsMigration, isFalse);
  });

  test('错误密钥无法通过认证', () async {
    final encrypted = await crypto.encrypt('secret', crypto.generateKey());

    expect(
      () => crypto.decrypt(encrypted, crypto.generateKey()),
      throwsFormatException,
    );
  });

  test('被篡改的密文无法通过认证', () async {
    final key = crypto.generateKey();
    final encrypted = await crypto.encrypt('secret', key);
    final bytes = base64Decode(encrypted);
    bytes[bytes.length - 17] ^= 0x01;
    final tampered = base64Encode(bytes);

    expect(() => crypto.decrypt(tampered, key), throwsFormatException);
  });

  test('AAD 不匹配时无法解密', () async {
    final key = crypto.generateKey();
    final encrypted = await crypto.encrypt(
      'secret',
      key,
      aad: utf8.encode('user-1:reader:item-1'),
    );

    expect(
      () => crypto.decrypt(
        encrypted,
        key,
        aad: utf8.encode('user-2:reader:item-1'),
      ),
      throwsFormatException,
    );
  });

  test('截断信封会被拒绝', () async {
    final key = Uint8List(32);
    final truncated = base64Encode(<int>[0x4f, 0x4e, 0x53, 0x32, 0x02]);

    expect(() => crypto.decrypt(truncated, key), throwsFormatException);
  });

  test('旧格式仅可读取并标记需要迁移', () async {
    final key = Uint8List.fromList(List<int>.generate(32, (index) => index));
    const legacy = 'AAECAwQFBgcICQoLZ+7Hi36m+IfQj5F0yIzUvSs0Gn3gAgZq4rAi';

    final result = await crypto.decryptEnvelope(legacy, key);

    expect(result.plaintext, 'legacy-data');
    expect(result.keyId, 'legacy');
    expect(result.needsMigration, isTrue);
    expect(crypto.isVersion2(legacy), isFalse);
  });
}
