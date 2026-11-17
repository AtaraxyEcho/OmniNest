import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/photos/data/photo_batch_archive_downloader.dart';
import 'package:omninest/features/photos/domain/photo_batch_download_ticket.dart';

void main() {
  test('照片 ZIP 中断后从半成品继续并仅发布完整文件', () async {
    final directory = await Directory.systemTemp.createTemp(
      'photo-batch-download-test-',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    final destination = File('${directory.path}/photos.zip');
    final partial = File('${destination.path}.omninest.part');
    final bytes = Uint8List.fromList(List<int>.generate(8, (index) => index));
    final adapter = _PlannedAdapter([
      _ResponsePlan(
        statusCode: 200,
        headers: const {
          'etag': ['"version-1"'],
        },
        stream: _interruptedStream(bytes.sublist(0, 4)),
      ),
      _ResponsePlan(
        statusCode: 206,
        headers: const {
          'etag': ['"version-1"'],
          'content-range': ['bytes 4-7/8'],
        },
        stream: Stream.value(bytes.sublist(4)),
      ),
    ]);
    final dio = Dio()..httpClientAdapter = adapter;
    final ticket = _ticket(bytes);

    await expectLater(
      downloadPhotoBatchArchive(
        dio: dio,
        ticket: ticket,
        destinationPath: destination.path,
      ),
      throwsA(isA<SocketException>()),
    );

    expect(await destination.exists(), isFalse);
    expect(await partial.readAsBytes(), bytes.sublist(0, 4));

    await downloadPhotoBatchArchive(
      dio: dio,
      ticket: ticket,
      destinationPath: destination.path,
    );

    expect(adapter.requests.last.headers['Range'], 'bytes=4-');
    expect(await destination.readAsBytes(), bytes);
    expect(await partial.exists(), isFalse);
    expect(await File('${partial.path}.resume.json').exists(), isFalse);
  });
}

PhotoBatchDownloadTicket _ticket(Uint8List bytes) {
  return PhotoBatchDownloadTicket(
    url: 'https://storage.example/photos.zip',
    fileName: 'photos.zip',
    sizeBytes: bytes.length,
    expiresAt: DateTime.now().add(const Duration(minutes: 15)),
    sha256: sha256.convert(bytes).toString(),
  );
}

Stream<Uint8List> _interruptedStream(Uint8List bytes) async* {
  yield bytes;
  throw const SocketException('connection interrupted');
}

class _PlannedAdapter implements HttpClientAdapter {
  _PlannedAdapter(this.plans);

  final List<_ResponsePlan> plans;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final plan = plans.removeAt(0);
    return ResponseBody(plan.stream, plan.statusCode, headers: plan.headers);
  }

  @override
  void close({bool force = false}) {}
}

class _ResponsePlan {
  const _ResponsePlan({
    required this.statusCode,
    required this.headers,
    required this.stream,
  });

  final int statusCode;
  final Map<String, List<String>> headers;
  final Stream<Uint8List> stream;
}
