import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/platform/desktop/desktop_single_instance.dart';

void main() {
  group('extractDesktopDeepLink', () {
    test('从参数中提取 omninest:// 深链', () {
      expect(
        extractDesktopDeepLink(['--foo', 'omninest://video/1']),
        'omninest://video/1',
      );
    });

    test('无深链时返回 null，大小写不敏感识别 scheme', () {
      expect(extractDesktopDeepLink(['--foo', 'path']), isNull);
      expect(
        extractDesktopDeepLink(['OMNINEST://music/2']),
        'OMNINEST://music/2',
      );
    });
  });

  group('forwardSingleInstanceActivate', () {
    test('向监听端口发送激活信号与深链', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      final received = Completer<String>();
      server.listen((socket) {
        socket
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
              if (!received.isCompleted) {
                received.complete(line);
              }
            });
      });

      final ok = await forwardSingleInstanceActivate(
        port: server.port,
        arguments: ['omninest://photos/9'],
      );
      expect(ok, isTrue);
      expect(await received.future.timeout(const Duration(seconds: 2)),
          'OMNINEST_ACTIVATE omninest://photos/9');
    });

    test('无深链时仅发送激活前缀', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      final received = Completer<String>();
      server.listen((socket) {
        socket
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
              if (!received.isCompleted) {
                received.complete(line);
              }
            });
      });

      final ok = await forwardSingleInstanceActivate(port: server.port);
      expect(ok, isTrue);
      expect(await received.future.timeout(const Duration(seconds: 2)),
          'OMNINEST_ACTIVATE');
    });

    test('端口无监听时返回 false（放弃保护或转发失败）', () async {
      final ok = await forwardSingleInstanceActivate(port: 1);
      expect(ok, isFalse);
    });
  });

  group('handleSingleInstanceControlLine', () {
    setUp(() {
      debugOverrideActivateMainWindow = () {};
    });
    tearDown(() {
      debugOverrideActivateMainWindow = null;
    });

    test('omninest 深链转交 desktopDeepLinkHandler', () {
      Uri? got;
      desktopDeepLinkHandler = (uri) => got = uri;
      addTearDown(() => desktopDeepLinkHandler = null);

      handleSingleInstanceControlLine('OMNINEST_ACTIVATE omninest://reader/3');
      expect(got?.toString(), 'omninest://reader/3');
    });

    test('非激活前缀或非法 scheme 不触发 handler', () {
      var called = 0;
      desktopDeepLinkHandler = (_) => called++;
      addTearDown(() => desktopDeepLinkHandler = null);

      handleSingleInstanceControlLine('NOPE');
      handleSingleInstanceControlLine('OMNINEST_ACTIVATE https://x');
      handleSingleInstanceControlLine('OMNINEST_ACTIVATE');
      expect(called, 0);
    });
  });

  test('端口契约常量与 runner 注释一致（47683）', () {
    expect(kOmniNestSingleInstancePort, 47683);
  });
}
