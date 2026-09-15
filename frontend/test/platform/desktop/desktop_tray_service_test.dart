import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/platform/desktop/desktop_tray_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const trayChannel = MethodChannel('tray_manager');
  final channelCalls = <MethodCall>[];

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(trayChannel, (call) async {
          channelCalls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(trayChannel, null);
    channelCalls.clear();
  });

  test('托盘右键菜单包含应用名标题、显示主窗口与退出三段结构', () async {
    final service = DesktopTrayService();
    await service.init();

    final contextCall = channelCalls.singleWhere(
      (call) => call.method == 'setContextMenu',
    );
    final menu =
        (contextCall.arguments as Map<Object?, Object?>)['menu']
            as Map<Object?, Object?>;
    final items = menu['items'] as List<Object?>;
    final labels =
        items
            .map((item) => (item as Map<Object?, Object?>)['label'] as String)
            .toList();
    final types =
        items.map((item) => (item as Map<Object?, Object?>)['type']).toList();
    final disabled =
        items
            .where(
              (item) => (item as Map<Object?, Object?>)['type'] == 'normal',
            )
            .map((item) => (item as Map<Object?, Object?>)['disabled'] as bool)
            .toList();
    final actionKeys =
        items
            .where(
              (item) => (item as Map<Object?, Object?>)['type'] != 'separator',
            )
            .map((item) => (item as Map<Object?, Object?>)['key'])
            .toList();

    expect(labels, <String>['OmniNest', '', '显示主窗口', '', '退出']);
    expect(types, <String?>[
      'normal',
      'separator',
      'normal',
      'separator',
      'normal',
    ]);
    expect(disabled, <bool>[true, false, false]);
    expect(actionKeys, <String?>['brand', 'show', 'quit']);
  });
}
