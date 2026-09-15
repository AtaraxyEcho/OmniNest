import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/preferences/app_bootstrap_data.dart';
import 'package:omninest/platform/desktop/desktop_tray_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const trayChannel = MethodChannel('tray_manager');
  const windowFrameChannel = MethodChannel('omninest/window_frame');
  final channelCalls = <MethodCall>[];
  final frameChannelCalls = <MethodCall>[];

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(trayChannel, (call) async {
          channelCalls.add(call);
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowFrameChannel, (call) async {
          frameChannelCalls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(trayChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowFrameChannel, null);
    channelCalls.clear();
    frameChannelCalls.clear();
  });

  List<Map<Object?, Object?>> menuItems() {
    final contextCall = channelCalls.singleWhere(
      (call) => call.method == 'setContextMenu',
    );
    final menu =
        (contextCall.arguments as Map<Object?, Object?>)['menu']
            as Map<Object?, Object?>;
    return (menu['items'] as List<Object?>)
        .map((item) => item as Map<Object?, Object?>)
        .toList();
  }

  void expectThreeSectionStructure(List<Map<Object?, Object?>> items) {
    final types = items.map((item) => item['type']).toList();
    final disabled =
        items
            .where((item) => item['type'] == 'normal')
            .map((item) => item['disabled'] as bool)
            .toList();
    final actionKeys =
        items
            .where((item) => item['type'] != 'separator')
            .map((item) => item['key'])
            .toList();

    expect(items, hasLength(5));
    expect(types, <String?>[
      'normal',
      'separator',
      'normal',
      'separator',
      'normal',
    ]);
    expect(disabled, <bool>[true, false, false]);
    expect(actionKeys, <String?>['brand', 'show', 'quit']);
  }

  test('托盘右键菜单文案按设备语言进入 ARB 并保持三段结构', () async {
    SharedPreferences.setMockInitialValues({localeDeviceLanguageKey: 'zh'});
    final service = DesktopTrayService();
    await service.init();

    expect(DesktopTrayService.instance, same(service));
    final items = menuItems();
    expectThreeSectionStructure(items);
    expect(items.map((item) => item['label']), <String>[
      'OmniNest',
      '',
      '显示主窗口',
      '',
      '退出',
    ]);
  });

  test('运行期语言变化时托盘菜单按 ARB 刷新', () async {
    SharedPreferences.setMockInitialValues({localeDeviceLanguageKey: 'zh'});
    final service = DesktopTrayService();
    await service.init();

    channelCalls.clear();
    await service.applyLanguage('en');

    final items = menuItems();
    expectThreeSectionStructure(items);
    expect(items.map((item) => item['label']), <String>[
      'OmniNest',
      '',
      'Show Main Window',
      '',
      'Quit',
    ]);
  });

  test('右键弹出菜单请求前台归属，关闭后补投收尾消息', () async {
    SharedPreferences.setMockInitialValues({localeDeviceLanguageKey: 'zh'});
    final service = DesktopTrayService();
    await service.init();

    channelCalls.clear();
    frameChannelCalls.clear();
    await service.popUpMenu();

    final popupCall = channelCalls.singleWhere(
      (call) => call.method == 'popUpContextMenu',
    );
    expect(
      (popupCall.arguments as Map<Object?, Object?>)['bringAppToFront'],
      isTrue,
    );
    expect(frameChannelCalls.map((call) => call.method), <String>[
      'finishTrayMenuPopup',
    ]);
  });
}
