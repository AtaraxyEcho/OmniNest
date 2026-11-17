import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/security/encrypted_file_vault.dart';
import 'package:omninest/core/security/offline_key_store_base.dart';

void main() {
  late Directory temporaryDirectory;
  late EncryptedFileVault vault;
  late OfflineFileContext context;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('vault-test-');
    vault = EncryptedFileVault(
      keyStore: _FixedOfflineKeyStore(),
      chunkSize: 4096,
    );
    context = const OfflineFileContext(
      userId: 'user-1',
      cacheType: 'reader-book',
      businessId: 'item-1',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('分块加密文件可解密到内存和文件', () async {
    final plaintext = Uint8List.fromList(
      List<int>.generate(9500, (index) => index % 251),
    );
    final source = File('${temporaryDirectory.path}/source.bin');
    final encrypted = File('${temporaryDirectory.path}/encrypted.onf');
    final restored = File('${temporaryDirectory.path}/restored.bin');
    await source.writeAsBytes(plaintext);

    await vault.encryptFile(
      source: source,
      destination: encrypted,
      context: context,
    );
    final decrypted = await vault.decryptToBytes(
      source: encrypted,
      context: context,
    );
    await vault.decryptToFile(
      source: encrypted,
      destination: restored,
      context: context,
    );

    expect(await encrypted.readAsBytes(), isNot(equals(plaintext)));
    expect(decrypted, plaintext);
    expect(await restored.readAsBytes(), plaintext);
  });

  test('内存字节可直接加密且不生成明文临时文件', () async {
    final plaintext = Uint8List.fromList(
      List<int>.generate(9500, (index) => index % 239),
    );
    final encrypted = File('${temporaryDirectory.path}/encrypted.onf');

    await vault.encryptBytes(
      bytes: plaintext,
      destination: encrypted,
      context: context,
    );

    expect(
      await vault.decryptToBytes(source: encrypted, context: context),
      plaintext,
    );
    expect(
      temporaryDirectory.listSync().whereType<File>().map((file) => file.path),
      everyElement(isNot(contains('.plain'))),
    );
  });

  test('文件上下文不匹配时认证失败', () async {
    final source = File('${temporaryDirectory.path}/source.bin');
    final encrypted = File('${temporaryDirectory.path}/encrypted.onf');
    await source.writeAsBytes(List<int>.generate(5000, (index) => index % 255));
    await vault.encryptFile(
      source: source,
      destination: encrypted,
      context: context,
    );

    expect(
      () => vault.decryptToBytes(
        source: encrypted,
        context: const OfflineFileContext(
          userId: 'user-2',
          cacheType: 'reader-book',
          businessId: 'item-1',
        ),
      ),
      throwsFormatException,
    );
  });

  test('篡改分块密文时认证失败', () async {
    final source = File('${temporaryDirectory.path}/source.bin');
    final encrypted = File('${temporaryDirectory.path}/encrypted.onf');
    await source.writeAsBytes(List<int>.generate(5000, (index) => index % 255));
    await vault.encryptFile(
      source: source,
      destination: encrypted,
      context: context,
    );
    final bytes = await encrypted.readAsBytes();
    bytes[bytes.length - 17] ^= 0x01;
    await encrypted.writeAsBytes(bytes);

    expect(
      () => vault.decryptToBytes(source: encrypted, context: context),
      throwsFormatException,
    );
  });

  test('内存解密在分配前执行大小限制', () async {
    final source = File('${temporaryDirectory.path}/source.bin');
    final encrypted = File('${temporaryDirectory.path}/encrypted.onf');
    await source.writeAsBytes(List<int>.filled(5000, 1));
    await vault.encryptFile(
      source: source,
      destination: encrypted,
      context: context,
    );

    expect(
      () => vault.decryptToBytes(
        source: encrypted,
        context: context,
        maxBytes: 4096,
      ),
      throwsFormatException,
    );
  });
}

class _FixedOfflineKeyStore implements OfflineKeyStore {
  final Uint8List _key = Uint8List.fromList(
    List<int>.generate(32, (index) => index),
  );

  @override
  Future<OfflineMasterKey> readOrCreate(String userId) async {
    return OfflineMasterKey(keyId: 'master-v1', bytes: _key);
  }

  @override
  Future<void> delete(String userId) async {}
}
