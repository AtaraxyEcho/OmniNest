import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:omninest/core/security/offline_crypto.dart';
import 'package:omninest/core/security/offline_key_store_base.dart';

/// 离线加密文件的身份上下文。
class OfflineFileContext {
  const OfflineFileContext({
    required this.userId,
    required this.cacheType,
    required this.businessId,
  });

  final String userId;
  final String cacheType;
  final String businessId;

  List<int> associatedData(String purpose) {
    return utf8.encode(
      '$userId\u0000$cacheType\u0000$businessId\u0000$purpose',
    );
  }
}

/// 使用独立文件密钥和分块 AES-GCM 管理离线文件。
class EncryptedFileVault {
  EncryptedFileVault({
    required OfflineKeyStore keyStore,
    OfflineCrypto crypto = const OfflineCrypto(),
    int chunkSize = 1024 * 1024,
  }) : _keyStore = keyStore,
       _crypto = crypto,
       _chunkSize = chunkSize {
    if (chunkSize < 4096 || chunkSize > 16 * 1024 * 1024) {
      throw ArgumentError.value(chunkSize, 'chunkSize', '分块大小超出允许范围');
    }
  }

  static const _magic = <int>[0x4f, 0x4e, 0x46, 0x32];
  static const _version = 2;
  static const _algorithmId = 1;
  static const _nonceLength = 12;
  static const _tagLength = 16;
  static const _fixedHeaderLength = 21;

  final OfflineKeyStore _keyStore;
  final OfflineCrypto _crypto;
  final int _chunkSize;

  /// 将明文文件加密为可认证的分块文件。
  Future<void> encryptFile({
    required File source,
    required File destination,
    required OfflineFileContext context,
  }) async {
    final plaintextLength = await source.length();
    RandomAccessFile? input;
    try {
      input = await source.open();
      await _encrypt(
        destination: destination,
        context: context,
        plaintextLength: plaintextLength,
        readChunk: input.read,
      );
    } finally {
      await input?.close();
    }
  }

  /// 将内存字节直接加密为文件，不落地明文临时文件。
  Future<void> encryptBytes({
    required Uint8List bytes,
    required File destination,
    required OfflineFileContext context,
  }) async {
    var offset = 0;
    await _encrypt(
      destination: destination,
      context: context,
      plaintextLength: bytes.length,
      readChunk: (maximumLength) async {
        final end =
            offset + maximumLength < bytes.length
                ? offset + maximumLength
                : bytes.length;
        final chunk = bytes.sublist(offset, end);
        offset = end;
        return chunk;
      },
    );
  }

  /// 解密文件到内存，并在读取前执行明文大小限制。
  Future<Uint8List> decryptToBytes({
    required File source,
    required OfflineFileContext context,
    int maxBytes = 512 * 1024 * 1024,
  }) async {
    final output = BytesBuilder(copy: false);
    await _decryptChunks(
      source: source,
      context: context,
      maxBytes: maxBytes,
      onChunk: (chunk) async => output.add(chunk),
    );
    return output.takeBytes();
  }

  /// 将加密文件流式解密到另一个文件。
  Future<void> decryptToFile({
    required File source,
    required File destination,
    required OfflineFileContext context,
  }) async {
    final temporary = File('${destination.path}.decrypting');
    await destination.parent.create(recursive: true);
    await _deleteIfExists(temporary);
    RandomAccessFile? output;
    try {
      output = await temporary.open(mode: FileMode.write);
      await _decryptChunks(
        source: source,
        context: context,
        onChunk: output.writeFrom,
      );
      await output.flush();
      await output.close();
      output = null;
      await _deleteIfExists(destination);
      await temporary.rename(destination.path);
    } finally {
      await output?.close();
      await _deleteIfExists(temporary);
    }
  }

  Future<void> _encrypt({
    required File destination,
    required OfflineFileContext context,
    required int plaintextLength,
    required Future<List<int>> Function(int maximumLength) readChunk,
  }) async {
    final masterKey = await _keyStore.readOrCreate(context.userId);
    final fileKey = _crypto.generateKey();
    final wrappedKey = await _crypto.encrypt(
      base64Encode(fileKey),
      masterKey.bytes,
      keyId: masterKey.keyId,
      aad: context.associatedData('wrapped-dek'),
    );
    final temporary = File('${destination.path}.encrypting');
    await destination.parent.create(recursive: true);
    await _deleteIfExists(temporary);

    RandomAccessFile? output;
    try {
      output = await temporary.open(mode: FileMode.write);
      await _writeHeader(
        output,
        plaintextLength: plaintextLength,
        keyId: masterKey.keyId,
        wrappedKey: wrappedKey,
      );
      final algorithm = AesGcm.with256bits();
      var chunkIndex = 0;
      var processed = 0;
      while (processed < plaintextLength) {
        final remaining = plaintextLength - processed;
        final plaintext = await readChunk(
          remaining < _chunkSize ? remaining : _chunkSize,
        );
        if (plaintext.isEmpty) {
          throw const FormatException('明文数据提前结束');
        }
        final nonce = algorithm.newNonce();
        final secretBox = await algorithm.encrypt(
          plaintext,
          secretKey: SecretKey(fileKey),
          nonce: nonce,
          aad: _chunkAssociatedData(context, chunkIndex, plaintextLength),
        );
        await output.writeFrom(nonce);
        await output.writeFrom(_encodeUint32(secretBox.cipherText.length));
        await output.writeFrom(secretBox.cipherText);
        await output.writeFrom(secretBox.mac.bytes);
        processed += plaintext.length;
        chunkIndex++;
      }
      await output.flush();
      await output.close();
      output = null;
      await _deleteIfExists(destination);
      await temporary.rename(destination.path);
    } finally {
      await output?.close();
      await _deleteIfExists(temporary);
      fileKey.fillRange(0, fileKey.length, 0);
    }
  }

  Future<void> _decryptChunks({
    required File source,
    required OfflineFileContext context,
    required Future<void> Function(List<int> chunk) onChunk,
    int? maxBytes,
  }) async {
    RandomAccessFile? input;
    Uint8List? fileKey;
    try {
      input = await source.open();
      final header = await _readHeader(input);
      if (maxBytes != null && header.plaintextLength > maxBytes) {
        throw const FormatException('离线文件超过内存解密限制');
      }
      final masterKey = await _keyStore.readOrCreate(context.userId);
      if (masterKey.keyId != header.keyId) {
        throw const FormatException('离线文件密钥版本不可用');
      }
      final encodedFileKey = await _crypto.decrypt(
        header.wrappedKey,
        masterKey.bytes,
        aad: context.associatedData('wrapped-dek'),
      );
      final decodedFileKey = base64Decode(encodedFileKey);
      if (decodedFileKey.length != 32) {
        throw const FormatException('离线文件密钥长度无效');
      }
      fileKey = Uint8List.fromList(decodedFileKey);

      var chunkIndex = 0;
      var produced = 0;
      while (produced < header.plaintextLength) {
        final nonce = await _readExact(input, _nonceLength);
        final cipherLengthBytes = await _readExact(input, 4);
        final cipherLength = _decodeUint32(cipherLengthBytes);
        if (cipherLength <= 0 || cipherLength > header.chunkSize) {
          throw const FormatException('离线文件分块长度无效');
        }
        final ciphertext = await _readExact(input, cipherLength);
        final tag = await _readExact(input, _tagLength);
        try {
          final plaintext = await AesGcm.with256bits().decrypt(
            SecretBox(ciphertext, nonce: nonce, mac: Mac(tag)),
            secretKey: SecretKey(fileKey),
            aad: _chunkAssociatedData(
              context,
              chunkIndex,
              header.plaintextLength,
            ),
          );
          if (produced + plaintext.length > header.plaintextLength) {
            throw const FormatException('离线文件明文长度溢出');
          }
          await onChunk(plaintext);
          produced += plaintext.length;
          chunkIndex++;
        } on SecretBoxAuthenticationError {
          throw const FormatException('离线文件分块认证失败');
        }
      }
      if (await input.position() != await input.length()) {
        throw const FormatException('离线文件包含未认证尾部数据');
      }
    } finally {
      await input?.close();
      fileKey?.fillRange(0, fileKey.length, 0);
    }
  }

  Future<void> _writeHeader(
    RandomAccessFile output, {
    required int plaintextLength,
    required String keyId,
    required String wrappedKey,
  }) async {
    final keyIdBytes = utf8.encode(keyId);
    final wrappedKeyBytes = utf8.encode(wrappedKey);
    if (keyIdBytes.isEmpty || keyIdBytes.length > 255) {
      throw const FormatException('离线文件密钥标识长度无效');
    }
    if (wrappedKeyBytes.isEmpty || wrappedKeyBytes.length > 65535) {
      throw const FormatException('离线文件包装密钥长度无效');
    }
    await output.writeFrom(_magic);
    await output.writeByte(_version);
    await output.writeByte(_algorithmId);
    await output.writeFrom(_encodeUint32(_chunkSize));
    await output.writeFrom(_encodeUint64(plaintextLength));
    await output.writeFrom(_encodeUint16(wrappedKeyBytes.length));
    await output.writeByte(keyIdBytes.length);
    await output.writeFrom(keyIdBytes);
    await output.writeFrom(wrappedKeyBytes);
  }

  Future<_EncryptedFileHeader> _readHeader(RandomAccessFile input) async {
    final fixed = await _readExact(input, _fixedHeaderLength);
    if (!_hasMagic(fixed) || fixed[4] != _version || fixed[5] != _algorithmId) {
      throw const FormatException('离线文件信封版本无效');
    }
    final chunkSize = _decodeUint32(fixed.sublist(6, 10));
    final plaintextLength = _decodeUint64(fixed.sublist(10, 18));
    final wrappedKeyLength = _decodeUint16(fixed.sublist(18, 20));
    final keyIdLength = fixed[20];
    if (chunkSize < 4096 ||
        chunkSize > 16 * 1024 * 1024 ||
        wrappedKeyLength == 0 ||
        keyIdLength == 0) {
      throw const FormatException('离线文件信封参数无效');
    }
    final keyId = utf8.decode(await _readExact(input, keyIdLength));
    final wrappedKey = utf8.decode(await _readExact(input, wrappedKeyLength));
    return _EncryptedFileHeader(
      chunkSize: chunkSize,
      plaintextLength: plaintextLength,
      keyId: keyId,
      wrappedKey: wrappedKey,
    );
  }

  List<int> _chunkAssociatedData(
    OfflineFileContext context,
    int chunkIndex,
    int plaintextLength,
  ) {
    return <int>[
      ...context.associatedData('chunk'),
      ..._encodeUint64(chunkIndex),
      ..._encodeUint64(plaintextLength),
    ];
  }

  Future<Uint8List> _readExact(RandomAccessFile input, int length) async {
    final bytes = await input.read(length);
    if (bytes.length != length) {
      throw const FormatException('离线文件提前结束');
    }
    return bytes;
  }

  bool _hasMagic(List<int> bytes) {
    for (var index = 0; index < _magic.length; index++) {
      if (bytes[index] != _magic[index]) {
        return false;
      }
    }
    return true;
  }

  Uint8List _encodeUint16(int value) {
    return Uint8List(2)..buffer.asByteData().setUint16(0, value);
  }

  Uint8List _encodeUint32(int value) {
    return Uint8List(4)..buffer.asByteData().setUint32(0, value);
  }

  Uint8List _encodeUint64(int value) {
    return Uint8List(8)..buffer.asByteData().setUint64(0, value);
  }

  int _decodeUint16(List<int> bytes) {
    return Uint8List.fromList(bytes).buffer.asByteData().getUint16(0);
  }

  int _decodeUint32(List<int> bytes) {
    return Uint8List.fromList(bytes).buffer.asByteData().getUint32(0);
  }

  int _decodeUint64(List<int> bytes) {
    return Uint8List.fromList(bytes).buffer.asByteData().getUint64(0);
  }

  Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }
}

class _EncryptedFileHeader {
  const _EncryptedFileHeader({
    required this.chunkSize,
    required this.plaintextLength,
    required this.keyId,
    required this.wrappedKey,
  });

  final int chunkSize;
  final int plaintextLength;
  final String keyId;
  final String wrappedKey;
}
