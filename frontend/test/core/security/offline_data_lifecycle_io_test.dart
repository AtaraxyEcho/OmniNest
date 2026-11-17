import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/security/offline_data_lifecycle_io.dart';

void main() {
  test('原生平台初始化时删除旧版明文阅读缓存', () async {
    final root = await Directory.systemTemp.createTemp(
      'offline-data-initialization-',
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final documents = Directory('${root.path}/documents');
    final temporary = Directory('${root.path}/temporary');
    final documentCache = Directory('${documents.path}/reader_cache');
    final temporaryCache = Directory('${temporary.path}/reader_cache');
    final retainedFile = File('${documents.path}/retained.txt');
    await documentCache.create(recursive: true);
    await temporaryCache.create(recursive: true);
    await File('${documentCache.path}/book.epub').writeAsString('plaintext');
    await File('${temporaryCache.path}/book.epub').writeAsString('plaintext');
    await retainedFile.writeAsString('retained');

    await initializeOfflineDataLifecycle(
      documentsDirectoryResolver: () async => documents,
      temporaryDirectoryResolver: () async => temporary,
    );

    expect(await documentCache.exists(), isFalse);
    expect(await temporaryCache.exists(), isFalse);
    expect(await retainedFile.exists(), isTrue);
  });
}
