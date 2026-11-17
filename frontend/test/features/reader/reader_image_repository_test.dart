import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/security/encrypted_file_vault.dart';
import 'package:omninest/core/security/offline_key_store_base.dart';
import 'package:omninest/core/storage/local_database.dart';
import 'package:omninest/features/reader/data/reader_image_repository_io.dart';

void main() {
  late Directory temporaryDirectory;
  late LocalDatabase database;
  late EncryptedFileVault vault;
  late IoReaderImageRepository repository;

  IoReaderImageRepository repositoryFor(String userId) {
    return IoReaderImageRepository(
      database: database,
      userId: userId,
      vault: vault,
      rootDirectory: () async => temporaryDirectory,
    );
  }

  File singleEncryptedFile() {
    return temporaryDirectory
        .listSync(recursive: true)
        .whereType<File>()
        .singleWhere((file) => file.path.endsWith('.onf'));
  }

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'reader-image-test-',
    );
    database = LocalDatabase(NativeDatabase.memory());
    vault = EncryptedFileVault(
      keyStore: _FixedOfflineKeyStore(),
      chunkSize: 4096,
    );
    repository = repositoryFor('user-1');
  });

  tearDown(() async {
    await database.close();
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('图片正文保存为加密文件且 SQLite 仅保留索引', () async {
    final bytes = Uint8List.fromList(
      List<int>.generate(8192, (index) => index % 251),
    );

    await repository.saveImage(
      itemId: 'book-1',
      imagePath: 'images/cover.png',
      bytes: bytes,
      mimeType: 'image/png',
    );

    final row = await database.select(database.cachedReaderImages).getSingle();
    final encryptedFile = singleEncryptedFile();
    expect(row.userId, 'user-1');
    expect(row.sizeBytes, bytes.length);
    expect(row.storageKey, hasLength(64));
    expect(await encryptedFile.readAsBytes(), isNot(equals(bytes)));
    expect(
      await repository.loadImage(
        itemId: 'book-1',
        imagePath: 'images/cover.png',
      ),
      bytes,
    );
  });

  test('不同用户不能读取同一业务标识的图片缓存', () async {
    await repository.saveImage(
      itemId: 'book-1',
      imagePath: 'images/cover.png',
      bytes: Uint8List.fromList(<int>[1, 2, 3]),
    );
    final otherUserRepository = repositoryFor('user-2');

    expect(
      await otherUserRepository.loadImage(
        itemId: 'book-1',
        imagePath: 'images/cover.png',
      ),
      isNull,
    );
  });

  test('密文被篡改时删除损坏文件和索引', () async {
    await repository.saveImage(
      itemId: 'book-1',
      imagePath: 'images/cover.png',
      bytes: Uint8List.fromList(List<int>.filled(5000, 7)),
    );
    final encryptedFile = singleEncryptedFile();
    final encryptedBytes = await encryptedFile.readAsBytes();
    encryptedBytes[encryptedBytes.length - 17] ^= 1;
    await encryptedFile.writeAsBytes(encryptedBytes);

    expect(
      await repository.loadImage(
        itemId: 'book-1',
        imagePath: 'images/cover.png',
      ),
      isNull,
    );
    expect(await encryptedFile.exists(), isFalse);
    expect(await database.select(database.cachedReaderImages).get(), isEmpty);
  });

  test('索引存储键损坏时删除记录并返回未命中', () async {
    final now = DateTime.now();
    await database
        .into(database.cachedReaderImages)
        .insert(
          CachedReaderImagesCompanion.insert(
            userId: 'user-1',
            itemId: 'book-1',
            imagePath: 'images/cover.png',
            storageKey: '../invalid',
            sizeBytes: 3,
            cachedAt: now,
            lastAccessedAt: now,
          ),
        );

    expect(
      await repository.loadImage(
        itemId: 'book-1',
        imagePath: 'images/cover.png',
      ),
      isNull,
    );
    expect(await database.select(database.cachedReaderImages).get(), isEmpty);
  });

  test('过期清理同时删除加密文件和索引', () async {
    await repository.saveImage(
      itemId: 'book-1',
      imagePath: 'images/cover.png',
      bytes: Uint8List.fromList(<int>[1, 2, 3]),
    );
    final encryptedFile = singleEncryptedFile();
    await database
        .update(database.cachedReaderImages)
        .write(
          CachedReaderImagesCompanion(
            lastAccessedAt: Value(
              DateTime.now().subtract(const Duration(days: 2)),
            ),
          ),
        );

    await repository.cleanOld(maxAgeDays: 1);

    expect(await encryptedFile.exists(), isFalse);
    expect(await database.select(database.cachedReaderImages).get(), isEmpty);
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
