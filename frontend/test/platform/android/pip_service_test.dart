import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/platform/android/pip_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('omninest/pip');
  final calls = <MethodCall>[];
  bool inPip = false;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls.clear();
    inPip = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'setVideoPlaybackActive':
              return true;
            case 'isInPipMode':
              return inPip;
          }
          return null;
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('setVideoPlaybackActive 同步 isInPipMode 并通知监听者', () async {
    final service = PipService.instance();
    final events = <bool>[];
    final cancel = service.addListener(events.add);
    addTearDown(cancel);

    await service.setVideoPlaybackActive(active: true);
    expect(calls.map((c) => c.method), contains('setVideoPlaybackActive'));
    expect(calls.map((c) => c.method), contains('isInPipMode'));
    expect(service.isInPipMode, isFalse);
    expect(events, isEmpty);

    inPip = true;
    await service.refreshPipMode();
    expect(service.isInPipMode, isTrue);
    expect(events, [true]);
  });
}
