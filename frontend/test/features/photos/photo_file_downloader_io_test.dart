import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/photos/data/photo_file_downloader.dart';

class _StaticAdapter implements HttpClientAdapter {
  _StaticAdapter(this.bytes);

  final Uint8List bytes;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody(
      Stream.value(bytes),
      200,
      headers: <String, List<String>>{
        Headers.contentLengthHeader: <String>[bytes.length.toString()],
      },
    );
  }
}

class _InterruptedAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final partial = Uint8List.fromList(const [1, 2, 3]);
    return ResponseBody(
      Stream<Uint8List>.fromFutures(<Future<Uint8List>>[
        Future.value(partial),
        Future<Uint8List>.error(const SocketException('download interrupted')),
      ]),
      200,
      headers: <String, List<String>>{
        Headers.contentLengthHeader: const <String>['16'],
      },
    );
  }
}

void main() {
  test('照片原片下载完成后原子发布且不残留半成品', () async {
    final directory = await Directory.systemTemp.createTemp(
      'photo-file-download-test-',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    final destination = File('${directory.path}/summer.jpg');
    final bytes = Uint8List.fromList(List<int>.generate(16, (index) => index));
    final dio = Dio()..httpClientAdapter = _StaticAdapter(bytes);

    await downloadPhotoFileToPath(
      dio: dio,
      url: 'https://minio.local/photos/summer.jpg?token=temporary',
      sizeBytes: bytes.length,
      destinationPath: destination.path,
    );

    expect(await destination.readAsBytes(), bytes);
    expect(await File('${destination.path}.omninest.part').exists(), isFalse);
  });

  test('照片原片下载中断时不发布目标文件', () async {
    final directory = await Directory.systemTemp.createTemp(
      'photo-file-download-interrupted-test-',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    final destination = File('${directory.path}/summer.jpg');
    final dio = Dio()..httpClientAdapter = _InterruptedAdapter();

    await expectLater(
      downloadPhotoFileToPath(
        dio: dio,
        url: 'https://minio.local/photos/summer.jpg?token=temporary',
        sizeBytes: 16,
        destinationPath: destination.path,
      ),
      throwsA(isA<SocketException>()),
    );

    expect(await destination.exists(), isFalse);
  });
}
