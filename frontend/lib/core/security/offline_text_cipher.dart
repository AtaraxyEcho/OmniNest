import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:omninest/core/security/offline_key_store_base.dart';

/// 离线敏感文本列加密器。
///
/// 与离线文件保险库共用平台安全存储中的主密钥，按用户 HKDF 派生独立列密钥，
/// 对章节正文、笔记与批注等敏感文本列做 AES-GCM 加密后落库：
/// - 密文带 `enc:v1:` 前缀与随机 nonce，同一明文两次加密的密文不同；
/// - 无前缀的历史明文行按明文读取（存量兼容），写入时一律加密；
/// - 解密失败（密钥缺失或数据被篡改）返回空字符串，按缓存未命中处理，
///   由上层从源数据重建，绝不把不可认证的内容当作正文返回。
class OfflineTextCipher {
  OfflineTextCipher({required OfflineKeyStore keyStore}) : _keyStore = keyStore;

  static const _prefix = 'enc:v1:';
  static const _keyInfo = 'omninest-offline-column-v1';
  static const _nonceLength = 12;

  final OfflineKeyStore _keyStore;
  final Map<String, SecretKey> _derivedKeys = {};

  /// 加密文本；空文本直接返回空串保持列语义。
  Future<String> encrypt(String userId, String plaintext) async {
    if (plaintext.isEmpty) {
      return '';
    }
    final key = await _columnKey(userId);
    final random = Random.secure();
    final nonce = List<int>.generate(_nonceLength, (_) => random.nextInt(256));
    final secretBox = await AesGcm.with256bits().encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      nonce: nonce,
    );
    final combined = [
      ...secretBox.nonce,
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ];
    return _prefix + base64Encode(combined);
  }

  /// 解密文本；历史明文（无前缀）原样返回，解密失败返回空串。
  Future<String> decrypt(String userId, String stored) async {
    if (stored.isEmpty || !stored.startsWith(_prefix)) {
      return stored;
    }
    try {
      final combined = base64Decode(stored.substring(_prefix.length));
      if (combined.length <= _nonceLength + 16) {
        return '';
      }
      final key = await _columnKey(userId);
      final secretBox = SecretBox(
        combined.sublist(_nonceLength, combined.length - 16),
        nonce: combined.sublist(0, _nonceLength),
        mac: Mac(combined.sublist(combined.length - 16)),
      );
      final clear = await AesGcm.with256bits().decrypt(
        secretBox,
        secretKey: key,
      );
      return utf8.decode(clear);
    } on Exception {
      return '';
    }
  }

  Future<SecretKey> _columnKey(String userId) async {
    final cached = _derivedKeys[userId];
    if (cached != null) {
      return cached;
    }
    final master = await _keyStore.readOrCreate(userId);
    final derived = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
      secretKey: SecretKey(master.bytes),
      nonce: List<int>.filled(32, 0),
      info: utf8.encode(_keyInfo),
    );
    _derivedKeys[userId] = derived;
    return derived;
  }
}
