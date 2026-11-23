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
    const testToken =
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

    test('向监听端口发送带令牌激活信号与深链并校验 OK 握手', () async {
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
              socket.write('OK\n');
              unawaited(socket.flush().whenComplete(socket.destroy));
            });
      });

      final ok = await forwardSingleInstanceActivate(
        port: server.port,
        arguments: ['omninest://photos/9'],
        tokenOverride: testToken,
      );
      expect(ok, isTrue);
      expect(
        await received.future.timeout(const Duration(seconds: 2)),
        'OMNINEST_ACTIVATE $testToken omninest://photos/9',
      );
    });

    test('无深链时仅发送激活前缀与令牌并等待 OK', () async {
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
              socket.write('OK\n');
              unawaited(socket.flush().whenComplete(socket.destroy));
            });
      });

      final ok = await forwardSingleInstanceActivate(
        port: server.port,
        tokenOverride: testToken,
      );
      expect(ok, isTrue);
      expect(
        await received.future.timeout(const Duration(seconds: 2)),
        'OMNINEST_ACTIVATE $testToken',
      );
    });

    test('对端未回写 OK 时超时返回 false', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((socket) {
        socket.listen((_) {});
      });

      final ok = await forwardSingleInstanceActivate(
        port: server.port,
        tokenOverride: testToken,
      );
      expect(ok, isFalse);
    });

    test('端口无监听时返回 false（放弃保护或转发失败）', () async {
      final ok = await forwardSingleInstanceActivate(
        port: 1,
        tokenOverride: testToken,
      );
      expect(ok, isFalse);
    });
  });

  group('handleSingleInstanceControlLine', () {
    const testToken =
        'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789';

    setUp(() {
      debugOverrideActivateMainWindow = () {};
    });
    tearDown(() {
      debugOverrideActivateMainWindow = null;
    });

    test('令牌匹配时 omninest 深链转交 desktopDeepLinkHandler', () {
      Uri? got;
      desktopDeepLinkHandler = (uri) => got = uri;
      addTearDown(() => desktopDeepLinkHandler = null);

      final accepted = handleSingleInstanceControlLine(
        'OMNINEST_ACTIVATE $testToken omninest://reader/3',
        expectedToken: testToken,
      );
      expect(accepted, isTrue);
      expect(got?.toString(), 'omninest://reader/3');
    });

    test('令牌缺失或错误时直接拒绝且不触发 handler', () {
      var called = 0;
      desktopDeepLinkHandler = (_) => called++;
      addTearDown(() => desktopDeepLinkHandler = null);

      expect(
        handleSingleInstanceControlLine(
          'OMNINEST_ACTIVATE wrong_token omninest://reader/3',
          expectedToken: testToken,
        ),
        isFalse,
      );
      expect(
        handleSingleInstanceControlLine(
          'OMNINEST_ACTIVATE',
          expectedToken: testToken,
        ),
        isFalse,
      );
      expect(
        handleSingleInstanceControlLine('NOPE', expectedToken: testToken),
        isFalse,
      );
      expect(called, 0);
    });
  });

  test('端口契约常量与 runner 注释一致（47683）', () {
    expect(kOmniNestSingleInstancePort, 47683);
  });
}
