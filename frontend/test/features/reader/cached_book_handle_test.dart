import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/data/cached_book_handle.dart';

void main() {
  test('文件句柄延迟打开并在关闭时清理会话文件', () async {
    final directory = await Directory.systemTemp.createTemp(
      'cached-book-handle-test-',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    final file = File('${directory.path}/book.session');
    var openCount = 0;
    var closeCount = 0;
    final handle = CachedBookHandle.file(
      openFile: () async {
        openCount++;
        await file.writeAsBytes(<int>[1, 2, 3, 4]);
        return file;
      },
      closeFile: (openedFile) async {
        closeCount++;
        if (openedFile != null && await openedFile.exists()) {
          await openedFile.delete();
        }
      },
    );

    expect(openCount, 0);
    expect(await handle.openFilePath(), file.path);
    expect(await handle.openFilePath(), file.path);
    expect(openCount, 1);
    expect(await handle.readBytes(maxBytes: 4), <int>[1, 2, 3, 4]);

    await handle.close();
    await handle.close();

    expect(closeCount, 1);
    expect(await file.exists(), isFalse);
  });

  test('内存句柄执行整包容量限制', () async {
    final handle = CachedBookHandle.memory(Uint8List(5));

    await expectLater(
      handle.readBytes(maxBytes: 4),
      throwsA(isA<FormatException>()),
    );
  });
}
