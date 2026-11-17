import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/features/reader/data/reader_file_downloader.dart';
import 'package:omninest/features/reader/domain/reader_file_ticket.dart';

void main() {
  group('ReaderFileDownloader', () {
    test(
      'resumes an interrupted download with a bounded Range request',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'omninest_reader_resume_',
        );
        addTearDown(() => directory.delete(recursive: true));
        final destination = File('${directory.path}/book.epub.part');
        final bytes = Uint8List.fromList(
          List<int>.generate(8, (index) => index),
        );
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
          downloadReaderFileToPath(
            dio: dio,
            ticket: ticket,
            destinationPath: destination.path,
          ),
          throwsA(isA<SocketException>()),
        );
        expect(await destination.length(), 4);
        expect(await File('${destination.path}.resume.json').exists(), isTrue);

        await downloadReaderFileToPath(
          dio: dio,
          ticket: ticket,
          destinationPath: destination.path,
        );

        expect(await destination.readAsBytes(), bytes);
        expect(adapter.requests, hasLength(2));
        expect(adapter.requests[1].headers['Range'], 'bytes=4-');
        expect(await File('${destination.path}.resume.json').exists(), isFalse);
      },
    );

    test(
      'streams a 64 MiB file with bounded chunks and digest validation',
      () async {
        const totalBytes = 64 * 1024 * 1024;
        const chunkBytes = 64 * 1024;
        final directory = await Directory.systemTemp.createTemp(
          'omninest_reader_capacity_',
        );
        addTearDown(() => directory.delete(recursive: true));
        final destination = File('${directory.path}/large-book.epub.part');
        final expectedDigest =
            await sha256
                .bind(
                  _generatedStream(
                    totalBytes: totalBytes,
                    chunkBytes: chunkBytes,
                  ),
                )
                .first;
        var maxObservedChunkBytes = 0;
        final adapter = _PlannedAdapter([
          _ResponsePlan(
            statusCode: 200,
            headers: const {
              'etag': ['"large-version-1"'],
            },
            stream: _generatedStream(
              totalBytes: totalBytes,
              chunkBytes: chunkBytes,
              onChunk: (length) {
                if (length > maxObservedChunkBytes) {
                  maxObservedChunkBytes = length;
                }
              },
            ),
          ),
        ]);
        final dio = Dio()..httpClientAdapter = adapter;
        final ticket = ReaderFileTicket(
          itemId: 'large-item-1',
          fileName: 'large-book.epub',
          downloadUrl: 'https://storage.example/large-book.epub',
          sizeBytes: totalBytes,
          sha256: expectedDigest.toString(),
          expiresAt: DateTime.now().add(const Duration(minutes: 15)),
        );

        await downloadReaderFileToPath(
          dio: dio,
          ticket: ticket,
          destinationPath: destination.path,
        );

        expect(await destination.length(), totalBytes);
        expect(maxObservedChunkBytes, lessThanOrEqualTo(chunkBytes));
        expect(adapter.requests, hasLength(1));
        expect(await File('${destination.path}.resume.json').exists(), isFalse);
      },
    );

    test('restarts from zero when the upstream ETag changes', () async {
      final directory = await Directory.systemTemp.createTemp(
        'omninest_reader_etag_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final destination = File('${directory.path}/book.epub.part');
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
            'etag': ['"version-2"'],
            'content-range': ['bytes 4-7/8'],
          },
          stream: Stream.value(bytes.sublist(4)),
        ),
        _ResponsePlan(
          statusCode: 200,
          headers: const {
            'etag': ['"version-2"'],
          },
          stream: Stream.value(bytes),
        ),
      ]);
      final dio = Dio()..httpClientAdapter = adapter;
      final ticket = _ticket(bytes);

      await expectLater(
        downloadReaderFileToPath(
          dio: dio,
          ticket: ticket,
          destinationPath: destination.path,
        ),
        throwsA(isA<SocketException>()),
      );
      await downloadReaderFileToPath(
        dio: dio,
        ticket: ticket,
        destinationPath: destination.path,
      );

      expect(await destination.readAsBytes(), bytes);
      expect(adapter.requests, hasLength(3));
      expect(adapter.requests[1].headers['Range'], 'bytes=4-');
      expect(adapter.requests[2].headers.containsKey('Range'), isFalse);
    });

    test('discards a partial file when the ticket digest changes', () async {
      final directory = await Directory.systemTemp.createTemp(
        'omninest_reader_ticket_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final destination = File('${directory.path}/book.epub.part');
      final firstBytes = Uint8List.fromList(
        List<int>.generate(8, (index) => index),
      );
      final replacementBytes = Uint8List.fromList(
        List<int>.generate(8, (index) => index + 10),
      );
      final adapter = _PlannedAdapter([
        _ResponsePlan(
          statusCode: 200,
          headers: const {
            'etag': ['"version-1"'],
          },
          stream: _interruptedStream(firstBytes.sublist(0, 4)),
        ),
        _ResponsePlan(
          statusCode: 200,
          headers: const {
            'etag': ['"version-2"'],
          },
          stream: Stream.value(replacementBytes),
        ),
      ]);
      final dio = Dio()..httpClientAdapter = adapter;

      await expectLater(
        downloadReaderFileToPath(
          dio: dio,
          ticket: _ticket(firstBytes),
          destinationPath: destination.path,
        ),
        throwsA(isA<SocketException>()),
      );
      await downloadReaderFileToPath(
        dio: dio,
        ticket: _ticket(replacementBytes),
        destinationPath: destination.path,
      );

      expect(await destination.readAsBytes(), replacementBytes);
      expect(adapter.requests, hasLength(2));
      expect(adapter.requests[1].headers.containsKey('Range'), isFalse);
    });

    test('removes a completed file when its digest does not match', () async {
      final directory = await Directory.systemTemp.createTemp(
        'omninest_reader_digest_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final destination = File('${directory.path}/book.epub.part');
      final bytes = Uint8List.fromList(List<int>.generate(8, (index) => index));
      final adapter = _PlannedAdapter([
        _ResponsePlan(
          statusCode: 200,
          headers: const {
            'etag': ['"version-1"'],
          },
          stream: Stream.value(bytes),
        ),
      ]);
      final dio = Dio()..httpClientAdapter = adapter;
      final ticket = ReaderFileTicket(
        itemId: 'item-1',
        fileName: 'book.epub',
        downloadUrl: 'https://storage.example/book.epub',
        sizeBytes: bytes.length,
        sha256: sha256.convert(Uint8List.fromList([9, 9, 9])).toString(),
        expiresAt: DateTime.now().add(const Duration(minutes: 15)),
      );

      await expectLater(
        downloadReaderFileToPath(
          dio: dio,
          ticket: ticket,
          destinationPath: destination.path,
        ),
        throwsA(
          isA<AppException>().having(
            (exception) => exception.code,
            'code',
            'READER_FILE_DIGEST_MISMATCH',
          ),
        ),
      );

      expect(await destination.exists(), isFalse);
      expect(await File('${destination.path}.resume.json').exists(), isFalse);
    });
  });
}

ReaderFileTicket _ticket(Uint8List bytes) {
  return ReaderFileTicket(
    itemId: 'item-1',
    fileName: 'book.epub',
    downloadUrl: 'https://storage.example/book.epub',
    sizeBytes: bytes.length,
    sha256: sha256.convert(bytes).toString(),
    expiresAt: DateTime.now().add(const Duration(minutes: 15)),
  );
}

Stream<Uint8List> _interruptedStream(Uint8List bytes) async* {
  yield bytes;
  throw const SocketException('connection interrupted');
}

Stream<Uint8List> _generatedStream({
  required int totalBytes,
  required int chunkBytes,
  void Function(int length)? onChunk,
}) async* {
  final chunk = Uint8List.fromList(
    List<int>.generate(chunkBytes, (index) => index % 251),
  );
  var remainingBytes = totalBytes;
  while (remainingBytes > 0) {
    final currentBytes =
        remainingBytes < chunkBytes ? remainingBytes : chunkBytes;
    onChunk?.call(currentBytes);
    yield Uint8List.sublistView(chunk, 0, currentBytes);
    remainingBytes -= currentBytes;
  }
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
