import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/photos/application/photo_backup_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('默认关闭且范围视为全部相册', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final settings = await container.read(
      photoBackupPreferencesControllerProvider.future,
    );
    expect(settings.enabled, isFalse);
    expect(settings.scope, PhotoBackupScope.all);
    expect(settings.selectedAlbumIds, isEmpty);
  });

  test('存量用户缺省范围键视为全部相册（行为兼容）', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      photoBackupBackgroundEnabledKey: true,
    });
    final prefs = await SharedPreferences.getInstance();
    final settings = readPhotoBackupSettingsFrom(prefs);
    expect(settings.enabled, isTrue);
    expect(settings.scope, PhotoBackupScope.all);
  });

  test('开启时持久化开关、范围与自选相册集合', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container
        .read(photoBackupPreferencesControllerProvider.notifier)
        .enable(
          scope: PhotoBackupScope.selected,
          selectedAlbumIds: {'album-1', 'album-2'},
        );

    final settings = await container.read(
      photoBackupPreferencesControllerProvider.future,
    );
    expect(settings.enabled, isTrue);
    expect(settings.scope, PhotoBackupScope.selected);
    expect(settings.selectedAlbumIds, {'album-1', 'album-2'});

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(photoBackupBackgroundEnabledKey), isTrue);
    expect(prefs.getString(photoBackupScopeKey), 'selected');
    expect(
      prefs.getStringList(photoBackupSelectedAlbumIdsKey),
      containsAll(['album-1', 'album-2']),
    );
  });

  test('关闭保留范围偏好便于再次开启', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container
        .read(photoBackupPreferencesControllerProvider.notifier)
        .enable(
          scope: PhotoBackupScope.selected,
          selectedAlbumIds: {'album-1'},
        );
    await container
        .read(photoBackupPreferencesControllerProvider.notifier)
        .disable();

    final settings = await container.read(
      photoBackupPreferencesControllerProvider.future,
    );
    expect(settings.enabled, isFalse);
    expect(settings.scope, PhotoBackupScope.selected);
    expect(settings.selectedAlbumIds, {'album-1'});
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(photoBackupBackgroundEnabledKey), isFalse);
  });

  test('网络策略缺省仅 Wi-Fi，可切换为含移动网络并持久化', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final initial = await container.read(
      photoBackupPreferencesControllerProvider.future,
    );
    expect(initial.networkPolicy, PhotoBackupNetworkPolicy.wifiOnly);

    await container
        .read(photoBackupPreferencesControllerProvider.notifier)
        .setNetworkPolicy(PhotoBackupNetworkPolicy.any);

    final updated = await container.read(
      photoBackupPreferencesControllerProvider.future,
    );
    expect(updated.networkPolicy, PhotoBackupNetworkPolicy.any);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(photoBackupNetworkPolicyKey), 'any');
  });
}
