// 测试断言依赖 legacy Menu/MenuItem 的 key/type/label 契约。
// ignore_for_file: deprecated_member_use

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/preferences/app_bootstrap_data.dart';
import 'package:omninest/core/widgets/brand_logo.dart';
import 'package:omninest/platform/desktop/desktop_tray_port.dart';
import 'package:omninest/platform/desktop/desktop_tray_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 记录托盘原生调用的假端口：不触碰 tray_manager FFI。
class _FakeTrayPort implements DesktopTrayPort {
  final List<TrayListener> listeners = <TrayListener>[];
  String? iconPath;
  bool? isTemplate;
  String? toolTip;
  Menu? menu;
  bool? bringAppToFront;
  int destroyCount = 0;

  List<Map<String, Object?>> menuItems() {
    final items = menu?.items ?? const <MenuItem>[];
    return [
      for (final item in items)
        <String, Object?>{
          'key': item.key,
          'type': item.type,
          'label': item.label ?? '',
          'disabled': item.disabled,
        },
    ];
  }

  @override
  void addListener(TrayListener listener) {
    listeners.add(listener);
  }

  @override
  void removeListener(TrayListener listener) {
    listeners.remove(listener);
  }

  @override
  Future<void> setIcon(String path, {bool isTemplate = false}) async {
    iconPath = path;
    this.isTemplate = isTemplate;
  }

  @override
  Future<void> setToolTip(String text) async {
    toolTip = text;
  }

  @override
  Future<void> setContextMenu(Menu value) async {
    menu = value;
  }

  @override
  Future<void> popUpContextMenu({bool bringAppToFront = false}) async {
    this.bringAppToFront = bringAppToFront;
  }

  @override
  Future<void> destroy() async {
    destroyCount += 1;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const windowFrameChannel = MethodChannel('omninest/window_frame');
  final frameChannelCalls = <MethodCall>[];

  late _FakeTrayPort tray;

  setUp(() {
    tray = _FakeTrayPort();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowFrameChannel, (call) async {
          frameChannelCalls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowFrameChannel, null);
    frameChannelCalls.clear();
  });

  void expectThreeSectionStructure(List<Map<String, Object?>> items) {
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
    final service = DesktopTrayService(tray: tray);
    await service.init();

    expect(DesktopTrayService.instance, same(service));
    expect(tray.toolTip, 'OmniNest');
    // 单元测试默认 target 为 Android，走 POSIX 托盘图（PNG）。
    expect(tray.iconPath, BrandLogo.assetPath);
    final items = tray.menuItems();
    expectThreeSectionStructure(items);
    expect(items.map((item) => item['label']).toList(), <String>[
      'OmniNest',
      '',
      '显示主窗口',
      '',
      '退出',
    ]);
  });

  test('运行期语言变化时托盘菜单按 ARB 刷新', () async {
    SharedPreferences.setMockInitialValues({localeDeviceLanguageKey: 'zh'});
    final service = DesktopTrayService(tray: tray);
    await service.init();

    await service.applyLanguage('en');

    final items = tray.menuItems();
    expectThreeSectionStructure(items);
    expect(items.map((item) => item['label']).toList(), <String>[
      'OmniNest',
      '',
      'Show Main Window',
      '',
      'Quit',
    ]);
  });

  test('右键弹出菜单请求前台归属，关闭后补投收尾消息', () async {
    SharedPreferences.setMockInitialValues({localeDeviceLanguageKey: 'zh'});
    final service = DesktopTrayService(tray: tray);
    await service.init();

    frameChannelCalls.clear();
    await service.popUpMenu();

    expect(tray.bringAppToFront, isTrue);
    expect(frameChannelCalls.map((call) => call.method), <String>[
      'finishTrayMenuPopup',
    ]);
  });

  test('buildTrayMenu 输出三段稳定 key 契约', () {
    final l10n = lookupAppLocalizations(const Locale('zh'));
    final menu = DesktopTrayService.buildTrayMenu(l10n);
    final items = menu.items ?? const <MenuItem>[];
    expect(items.map((item) => item.key), <String?>[
      'brand',
      null,
      'show',
      null,
      'quit',
    ]);
  });
}
