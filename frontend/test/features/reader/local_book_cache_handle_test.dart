import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/security/encrypted_file_vault.dart';
import 'package:omninest/core/security/offline_key_store_base.dart';
import 'package:omninest/features/reader/data/local_book_cache.dart';

void main() {
  test('原生阅读缓存按需生成会话明文并在关闭后删除', () async {
    final directory = await Directory.systemTemp.createTemp(
      'local-book-cache-test-',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    final plaintext = Uint8List.fromList(
      List<int>.generate(9500, (index) => index % 251),
    );
    final staleSession = File(
      '${directory.path}/stale.onf.plain.session.abandoned',
    );
    await staleSession.writeAsBytes(<int>[9]);
    final cache = LocalBookCache(
      userId: 'user-1',
      vault: EncryptedFileVault(
        keyStore: _FixedOfflineKeyStore(),
        chunkSize: 4096,
      ),
      cacheDirectoryResolver: (_) async => directory,
    );

    final handle = await cache.ensureCachedHandle(
      'item-1',
      nativeDownloader: (path) => File(path).writeAsBytes(plaintext),
    );
    final filesBeforeOpen = await directory.list().toList();
    expect(filesBeforeOpen.whereType<File>(), hasLength(1));
    expect(filesBeforeOpen.single.path, endsWith('.onf'));
    expect(await staleSession.exists(), isFalse);

    final sessionPath = await handle.openFilePath();
    final secondHandle = await cache.ensureCachedHandle('item-1');
    final secondSessionPath = await secondHandle.openFilePath();
    expect(sessionPath, isNotNull);
    expect(secondSessionPath, isNot(sessionPath));
    expect(await File(sessionPath!).readAsBytes(), plaintext);
    expect(sessionPath, contains('.plain.session.'));

    await handle.close();

    expect(await File(sessionPath).exists(), isFalse);
    expect(await File(secondSessionPath!).exists(), isTrue);
    await secondHandle.close();
    expect(await File(secondSessionPath).exists(), isFalse);
    expect(await cache.isCached('item-1'), isTrue);
  });

  test('并发请求同一本书只下载一次', () async {
    final directory = await Directory.systemTemp.createTemp(
      'local-book-cache-singleflight-',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    var downloads = 0;
    final cache = LocalBookCache(
      userId: 'user-1',
      vault: EncryptedFileVault(
        keyStore: _FixedOfflineKeyStore(),
        chunkSize: 4096,
      ),
      cacheDirectoryResolver: (_) async => directory,
    );
    Future<void> downloader(String path) async {
      downloads += 1;
      // 拉长窗口，确保两次调用真的重叠。
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await File(
        path,
      ).writeAsBytes(Uint8List.fromList(List<int>.filled(1024, 7)));
    }

    final handles = await Future.wait([
      cache.ensureCachedHandle('item-race', nativeDownloader: downloader),
      cache.ensureCachedHandle('item-race', nativeDownloader: downloader),
    ]);

    expect(downloads, 1);
    for (final handle in handles) {
      await handle.close();
    }
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
