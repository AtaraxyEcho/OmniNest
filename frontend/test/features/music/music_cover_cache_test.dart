import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/music/data/music_cover_cache.dart';
import 'package:omninest/features/music/domain/music_cover_paths.dart';

void main() {
  group('isMusicCoverApiPath', () {
    test('稳定 API 路径命中', () {
      expect(
        isMusicCoverApiPath(
          '/api/v1/music/covers/6f1d2c3a-1234-4abc-9def-000000000001',
        ),
        isTrue,
      );
      // 缩略图是同一资源下的子路径，必须共用封面专域缓存。
      expect(
        isMusicCoverApiPath(
          musicCoverThumbnailPath(
            '/api/v1/music/covers/6f1d2c3a-1234-4abc-9def-000000000001',
          )!,
        ),
        isTrue,
      );
    });

    test('外部 CDN 与数据地址不命中', () {
      expect(isMusicCoverApiPath('https://p1.music.126.net/abc.jpg'), isFalse);
      expect(
        isMusicCoverApiPath('https://y.gtimg.cn/music/photo.jpg'),
        isFalse,
      );
      expect(isMusicCoverApiPath('data:image/png;base64,AAAA'), isFalse);
      expect(isMusicCoverApiPath(''), isFalse);
      expect(isMusicCoverApiPath('/api/v1/files/abc/download-url'), isFalse);
    });
  });

  group('MusicCoverFileService', () {
    test('按流式类型发起请求并适配响应', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://localhost:9090/api/v1'));
      dio.httpClientAdapter = _StubAdapter(
        bodyBytes: Uint8List.fromList(utf8.encode('cover-bytes')),
        contentType: 'image/png',
        contentLength: 'cover-bytes'.length,
      );
      final service = MusicCoverFileService(dio);

      final response = await service.get('/music/covers/abc');

      expect(response.statusCode, 200);
      expect(response.contentLength, 'cover-bytes'.length);
      expect(response.fileExtension, '.png');
      final bytes = <int>[];
      await for (final chunk in response.content) {
        bytes.addAll(chunk);
      }
      expect(utf8.decode(bytes), 'cover-bytes');
    });

    test('immutable 缓存指令决定有效期内 30 天', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://localhost:9090/api/v1'));
      dio.httpClientAdapter = _StubAdapter(
        bodyBytes: Uint8List(4),
        contentType: 'image/jpeg',
        cacheControl: 'private, max-age=2592000, immutable',
      );
      final service = MusicCoverFileService(dio);

      final response = await service.get('/music/covers/abc');

      final validDays = response.validTill.difference(DateTime.now()).inDays;
      expect(validDays, inInclusiveRange(29, 30));
    });

    test('缺省缓存头时保守回退一周', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://localhost:9090/api/v1'));
      dio.httpClientAdapter = _StubAdapter(
        bodyBytes: Uint8List(4),
        contentType: 'image/jpeg',
      );
      final service = MusicCoverFileService(dio);

      final response = await service.get('/music/covers/abc');

      final validDays = response.validTill.difference(DateTime.now()).inDays;
      expect(validDays, inInclusiveRange(6, 7));
    });
  });
}

/// 固定响应适配器：模拟后端封面流式响应。
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter({
    required this.bodyBytes,
    required this.contentType,
    this.cacheControl,
    int? contentLength,
  }) : _explicitContentLength = contentLength;

  final Uint8List bodyBytes;
  final String contentType;
  final String? cacheControl;
  final int? _explicitContentLength;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody(
      Stream.value(bodyBytes),
      200,
      headers: {
        'content-type': [contentType],
        if (_explicitContentLength != null)
          Headers.contentLengthHeader: [_explicitContentLength.toString()],
        if (cacheControl != null) 'cache-control': [cacheControl!],
      },
    );
  }
}
