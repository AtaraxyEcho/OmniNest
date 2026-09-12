import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/platform/desktop/desktop_hotkey_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const hotkeyChannel = MethodChannel('dev.leanflutter.plugins/hotkey_manager');
  const hotkeyEventChannel = EventChannel(
    'dev.leanflutter.plugins/hotkey_manager_event',
  );

  final registeredCalls = <MethodCall>[];
  const MethodCodec methodCodec = StandardMethodCodec();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(hotkeyChannel, (call) async {
          registeredCalls.add(call);
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(hotkeyEventChannel.name, (
          ByteData? message,
        ) async {
          return methodCodec.encodeSuccessEnvelope(null);
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(hotkeyChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(hotkeyEventChannel.name, null);
    registeredCalls.clear();
  });

  test('媒体键注册使用显式 VK 码，禁止向原生层发送空 keyCode', () async {
    final service = DesktopHotkeyService();
    await service.registerMediaKeys();

    if (!Platform.isWindows) {
      expect(registeredCalls, isEmpty);
      return;
    }

    expect(registeredCalls, hasLength(3));
    expect(registeredCalls.every((call) => call.method == 'register'), isTrue);
    final keyCodes =
        registeredCalls
            .map((call) => (call.arguments as Map<Object?, Object?>)['keyCode'])
            .toList();
    expect(keyCodes, <int>[179, 176, 177]);
    final identifiers =
        registeredCalls
            .map(
              (call) => (call.arguments as Map<Object?, Object?>)['identifier'],
            )
            .toList();
    expect(identifiers, <String>[
      'omninest_media_play_pause',
      'omninest_media_next',
      'omninest_media_previous',
    ]);
  });
}
