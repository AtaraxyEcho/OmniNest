import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/photos/application/photo_backup_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('默认关闭', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      await container.read(photoBackupPreferencesControllerProvider.future),
      isFalse,
    );
  });

  test('开启后持久化并保持开启态', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container
        .read(photoBackupPreferencesControllerProvider.notifier)
        .setEnabled(true);

    expect(
      await container.read(photoBackupPreferencesControllerProvider.future),
      isTrue,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(photoBackupBackgroundEnabledKey), isTrue);
  });
}
