import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/window/desktop_close_action.dart';
import 'package:omninest/core/window/desktop_close_behavior_controller.dart';
import 'package:omninest/core/window/desktop_close_flow.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DesktopCloseFlow.instance.reset();
  });

  test('设置关闭行为偏好时同步写回本地存储，传 null 恢复每次询问', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(await container.read(desktopCloseBehaviorProvider.future), isNull);

    await container
        .read(desktopCloseBehaviorProvider.notifier)
        .setAction(DesktopCloseAction.exitApp);

    expect(
      container.read(desktopCloseBehaviorProvider).value,
      DesktopCloseAction.exitApp,
    );
    expect(
      await DesktopCloseFlow.instance.readRememberedAction(),
      DesktopCloseAction.exitApp,
    );

    await container.read(desktopCloseBehaviorProvider.notifier).setAction(null);

    expect(await DesktopCloseFlow.instance.readRememberedAction(), isNull);
  });
}
