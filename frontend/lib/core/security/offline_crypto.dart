import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as legacy_crypto;
import 'package:cryptography/cryptography.dart';

/// 离线数据认证加密工具。
///
/// 新写入统一使用 AES-256-GCM v2 信封，旧格式仅用于迁移读取。
class OfflineCrypto {
  const OfflineCrypto();

  static const _keyLength = 32;
  static const _nonceLength = 12;
  static const _tagLength = 16;
  static const _version = 2;
  static const _algorithmId = 1;
  static const _magic = <int>[0x4f, 0x4e, 0x53, 0x32];
  static const _aadPrefix = 'OmniNest.offline.v2';

  /// 生成随机 256 位密钥。
  Uint8List generateKey() {
    final random = Random.secure();
    return Uint8List.fromList(
      List.generate(_keyLength, (_) => random.nextInt(256)),
    );
  }

  /// 使用 AES-256-GCM 加密字符串并返回 Base64 信封。
  Future<String> encrypt(
    String plaintext,
    Uint8List key, {
    String keyId = 'default',
    List<int> aad = const <int>[],
  }) async {
    _validateKey(key);
    final keyIdBytes = utf8.encode(keyId);
    if (keyIdBytes.isEmpty || keyIdBytes.length > 255) {
      throw const FormatException('密钥标识长度无效');
    }

    final algorithm = AesGcm.with256bits();
    final nonce = algorithm.newNonce();
    final secretBox = await algorithm.encrypt(
      utf8.encode(plaintext),
      secretKey: SecretKey(key),
      nonce: nonce,
      aad: _buildAssociatedData(keyId, aad),
    );
    final output =
        BytesBuilder(copy: false)
          ..add(_magic)
          ..add(<int>[
            _version,
            _algorithmId,
            nonce.length,
            secretBox.mac.bytes.length,
            keyIdBytes.length,
          ])
          ..add(keyIdBytes)
          ..add(nonce)
          ..add(secretBox.cipherText)
          ..add(secretBox.mac.bytes);
    return base64Encode(output.takeBytes());
  }

  /// 解密 v2 或旧格式信封并返回迁移信息。
  Future<OfflineDecryptionResult> decryptEnvelope(
    String encryptedBase64,
    Uint8List key, {
    List<int> aad = const <int>[],
  }) async {
    _validateKey(key);
    final data = _decodeBase64(encryptedBase64);
    if (!_hasV2Magic(data)) {
      return OfflineDecryptionResult(
        plaintext: _decryptLegacy(data, key),
        keyId: 'legacy',
        needsMigration: true,
      );
    }
    return _decryptV2(data, key, aad);
  }

  /// 解密字符串，不返回迁移元数据。
  Future<String> decrypt(
    String encryptedBase64,
    Uint8List key, {
    List<int> aad = const <int>[],
  }) async {
    final result = await decryptEnvelope(encryptedBase64, key, aad: aad);
    return result.plaintext;
  }

  /// 判断密文是否为 v2 信封。
  bool isVersion2(String encryptedBase64) {
    try {
      return _hasV2Magic(base64Decode(encryptedBase64));
    } on FormatException {
      return false;
    }
  }

  Future<OfflineDecryptionResult> _decryptV2(
    Uint8List data,
    Uint8List key,
    List<int> aad,
  ) async {
    const fixedHeaderLength = 9;
    if (data.length < fixedHeaderLength) {
      throw const FormatException('密文信封不完整');
    }
    final version = data[4];
    final algorithmId = data[5];
    final nonceLength = data[6];
    final tagLength = data[7];
    final keyIdLength = data[8];
    if (version != _version ||
        algorithmId != _algorithmId ||
        nonceLength != _nonceLength ||
        tagLength != _tagLength ||
        keyIdLength == 0) {
      throw const FormatException('密文信封参数无效');
    }

    final keyIdEnd = fixedHeaderLength + keyIdLength;
    final nonceEnd = keyIdEnd + nonceLength;
    final ciphertextEnd = data.length - tagLength;
    if (nonceEnd > ciphertextEnd) {
      throw const FormatException('密文信封长度无效');
    }
    final keyId = utf8.decode(data.sublist(fixedHeaderLength, keyIdEnd));
    final nonce = data.sublist(keyIdEnd, nonceEnd);
    final ciphertext = data.sublist(nonceEnd, ciphertextEnd);
    final tag = data.sublist(ciphertextEnd);

    try {
      final plaintext = await AesGcm.with256bits().decrypt(
        SecretBox(ciphertext, nonce: nonce, mac: Mac(tag)),
        secretKey: SecretKey(key),
        aad: _buildAssociatedData(keyId, aad),
      );
      return OfflineDecryptionResult(
        plaintext: utf8.decode(plaintext),
        keyId: keyId,
        needsMigration: false,
      );
    } on SecretBoxAuthenticationError {
      throw const FormatException('密文认证失败');
    }
  }

  Uint8List _decodeBase64(String encryptedBase64) {
    try {
      return base64Decode(encryptedBase64);
    } on FormatException {
      throw const FormatException('密文 Base64 格式无效');
    }
  }

  bool _hasV2Magic(List<int> data) {
    if (data.length < _magic.length) {
      return false;
    }
    for (var index = 0; index < _magic.length; index++) {
      if (data[index] != _magic[index]) {
        return false;
      }
    }
    return true;
  }

  List<int> _buildAssociatedData(String keyId, List<int> aad) {
    return <int>[...utf8.encode('$_aadPrefix\u0000$keyId\u0000'), ...aad];
  }

  String _decryptLegacy(Uint8List data, Uint8List key) {
    if (data.length < _nonceLength + _tagLength) {
      throw const FormatException('旧密文格式无效');
    }
    final nonce = Uint8List.fromList(data.sublist(0, _nonceLength));
    final ciphertext = Uint8List.fromList(
      data.sublist(_nonceLength, data.length - _tagLength),
    );
    final tag = data.sublist(data.length - _tagLength);
    final expectedTag = _computeLegacyTag(key, nonce, ciphertext);
    if (!_constantTimeEqual(tag, expectedTag)) {
      throw const FormatException('旧密文校验失败');
    }
    final keyStream = _generateLegacyKeyStream(key, nonce, ciphertext.length);
    final plaintext = Uint8List(ciphertext.length);
    for (var index = 0; index < ciphertext.length; index++) {
      plaintext[index] = ciphertext[index] ^ keyStream[index];
    }
    return utf8.decode(plaintext);
  }

  Uint8List _generateLegacyKeyStream(
    Uint8List key,
    Uint8List nonce,
    int length,
  ) {
    final stream = Uint8List(length);
    var counter = 0;
    for (var offset = 0; offset < length; offset += 32) {
      final input = <int>[
        ...key,
        ...nonce,
        counter & 0xff,
        (counter >> 8) & 0xff,
      ];
      final hash = legacy_crypto.sha256.convert(input).bytes;
      for (var index = 0; index < 32 && offset + index < length; index++) {
        stream[offset + index] = hash[index];
      }
      counter++;
    }
    return stream;
  }

  Uint8List _computeLegacyTag(
    Uint8List key,
    Uint8List nonce,
    Uint8List ciphertext,
  ) {
    final digest = legacy_crypto.Hmac(
      legacy_crypto.sha256,
      key,
    ).convert(<int>[...nonce, ...ciphertext]);
    return Uint8List.fromList(digest.bytes.sublist(0, _tagLength));
  }

  bool _constantTimeEqual(List<int> first, List<int> second) {
    if (first.length != second.length) {
      return false;
    }
    var difference = 0;
    for (var index = 0; index < first.length; index++) {
      difference |= first[index] ^ second[index];
    }
    return difference == 0;
  }

  void _validateKey(Uint8List key) {
    if (key.length != _keyLength) {
      throw const FormatException('AES-256 密钥必须为 32 字节');
    }
  }
}

/// 离线密文解密结果。
class OfflineDecryptionResult {
  const OfflineDecryptionResult({
    required this.plaintext,
    required this.keyId,
    required this.needsMigration,
  });

  final String plaintext;
  final String keyId;
  final bool needsMigration;
}
