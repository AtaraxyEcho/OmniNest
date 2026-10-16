import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/platform/file_pick.dart';
import '../support/fake_file_pick.dart';

void main() {
  late FilePickGuard guard;

  tearDown(() => guard.restore());

  test('pickFiles 透传类型与扩展名，结果按需读取', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    guard = installFilePick(
      files: [FakePickedPlatformFile(name: 'Lyrics.LRC', bytes: bytes)],
    );

    final picked = await FilePick.pickFiles(
      allowedExtensions: const ['lrc', 'txt'],
    );

    expect(picked, hasLength(1));
    expect(picked.single.name, 'Lyrics.LRC');
    expect(picked.single.extension, 'lrc');
    expect(await picked.single.readBytes(), bytes);
    expect(picked.single.lengthSync(), 3);
    expect(await picked.single.length(), 3);
    expect(guard.fake.lastType, FileType.custom);
    expect(guard.fake.lastAllowedExtensions, ['lrc', 'txt']);
  });

  test('pickImages 走图片类型，取消选择时返回空列表', () async {
    guard = installFilePick();

    expect(await FilePick.pickImages(), isEmpty);
    expect(guard.fake.lastType, FileType.image);
    expect(guard.fake.lastAllowedExtensions, isNull);
  });

  test('有本地路径时 toXFile 用路径而不是内存副本', () async {
    guard = installFilePick(
      files: [
        FakePickedPlatformFile(name: 'book.epub', path: r'/tmp/book.epub'),
      ],
    );

    final picked = await FilePick.pickFiles(allowedExtensions: const ['epub']);
    final upload = await picked.single.toXFile(
      mimeType: 'application/epub+zip',
    );

    // XFile 的 IO 分支会忽略传入的 name，并只按 Platform.pathSeparator 切分，
    // 这里只锁住"用路径而不是把整本读进内存"这一条，与迁移前行为一致。
    expect(upload.path, r'/tmp/book.epub');
    expect(upload.mimeType, 'application/epub+zip');
  });

  test('无本地路径时 toXFile 回落到内存字节', () async {
    final bytes = Uint8List.fromList([9, 9]);
    guard = installFilePick(
      files: [FakePickedPlatformFile(name: 'cover.jpg', bytes: bytes)],
    );

    final picked = await FilePick.pickImages();
    final upload = await picked.single.toXFile(mimeType: 'image/jpeg');

    expect(await upload.readAsBytes(), bytes);
  });

  test('平台选择失败时异常交给调用方处理', () async {
    guard = installFilePick(error: StateError('盘已断开'));

    await expectLater(
      FilePick.pickFiles(allowedExtensions: const ['lrc']),
      throwsStateError,
    );
  });
}
