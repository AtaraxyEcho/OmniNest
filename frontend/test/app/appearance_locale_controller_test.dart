import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/appearance/application/appearance_controller.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/app/locale/application/locale_controller.dart';
import 'package:omninest/app/preferences/app_bootstrap_data.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/core/preferences/preference_snapshot.dart';
import 'package:omninest/core/preferences/preference_sync_service.dart';
import 'package:omninest/core/preferences/user_preferences_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('未登录时外观和语言从设备偏好恢复', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      appearanceDeviceModeKey: 'light',
      localeDeviceLanguageKey: 'en',
    });
    final container = _createContainer(
      session: const AuthSessionState.unauthenticated(),
    );
    addTearDown(container.dispose);

    container.read(appearanceControllerProvider);
    container.read(localeControllerProvider);
    await container.read(authSessionProvider.future);
    await _waitUntil(
      () =>
          container.read(appearanceControllerProvider) == ThemeMode.light &&
          container.read(localeControllerProvider) == 'en',
    );

    expect(container.read(appearanceControllerProvider), ThemeMode.light);
    expect(container.read(localeControllerProvider), 'en');
  });

  test('设备系统主题偏好恢复为 ThemeMode.system', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      appearanceDeviceModeKey: 'system',
    });
    final container = _createContainer(
      session: const AuthSessionState.unauthenticated(),
    );
    addTearDown(container.dispose);

    container.read(appearanceControllerProvider);
    await container.read(authSessionProvider.future);
    await _waitUntil(
      () => container.read(appearanceControllerProvider) == ThemeMode.system,
    );

    expect(container.read(appearanceControllerProvider), ThemeMode.system);
  });

  test('登录后远端偏好覆盖设备值并隔离不同用户', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      appearanceDeviceModeKey: 'system',
      localeDeviceLanguageKey: 'zh',
    });
    final syncService =
        _MemoryPreferenceSyncService()
          ..put('user-a', appearancePreferenceScope, <String, dynamic>{
            'themeMode': 'dark',
          })
          ..put('user-a', localePreferenceScope, <String, dynamic>{
            'language': 'en',
          })
          ..put('user-b', appearancePreferenceScope, <String, dynamic>{
            'themeMode': 'light',
          })
          ..put('user-b', localePreferenceScope, <String, dynamic>{
            'language': 'zh',
          });
    final container = _createContainer(
      session: _session('user-a'),
      syncService: syncService,
    );
    addTearDown(container.dispose);

    container.read(appearanceControllerProvider);
    container.read(localeControllerProvider);
    await container.read(authSessionProvider.future);
    await _waitUntil(
      () =>
          container.read(appearanceControllerProvider) == ThemeMode.dark &&
          container.read(localeControllerProvider) == 'en',
    );

    final sessionNotifier = container.read(authSessionProvider.notifier);
    (sessionNotifier as _MutableSessionNotifier).setSession(_session('user-b'));
    await _waitUntil(
      () =>
          container.read(appearanceControllerProvider) == ThemeMode.light &&
          container.read(localeControllerProvider) == 'zh',
    );

    expect(container.read(appearanceControllerProvider), ThemeMode.light);
    expect(container.read(localeControllerProvider), 'zh');
  });

  test('运行时修改同步写入设备和当前用户作用域', () async {
    final syncService = _MemoryPreferenceSyncService();
    final container = _createContainer(
      session: _session('user-a'),
      syncService: syncService,
    );
    addTearDown(container.dispose);

    container.read(appearanceControllerProvider);
    container.read(localeControllerProvider);
    await container.read(authSessionProvider.future);
    await _waitUntil(() => syncService.loadCount >= 2);

    await container
        .read(appearanceControllerProvider.notifier)
        .setThemeMode(ThemeMode.dark);
    await container.read(localeControllerProvider.notifier).setLanguage('en');

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(appearanceDeviceModeKey), 'dark');
    expect(preferences.getString(localeDeviceLanguageKey), 'en');
    expect(
      syncService.values['user-a::$appearancePreferenceScope']?['themeMode'],
      'dark',
    );
    expect(
      syncService.values['user-a::$localePreferenceScope']?['language'],
      'en',
    );
  });
}

ProviderContainer _createContainer({
  required AuthSessionState session,
  PreferenceSyncService? syncService,
}) {
  return ProviderContainer.test(
    overrides: [
      appBootstrapDataProvider.overrideWithValue(
        const AppBootstrapData(themeModeName: 'system', languageCode: 'zh'),
      ),
      preferenceSyncServiceProvider.overrideWithValue(
        syncService ?? _MemoryPreferenceSyncService(),
      ),
      authSessionProvider.overrideWith(() => _MutableSessionNotifier(session)),
    ],
  );
}

AuthSessionState _session(String userId) {
  return AuthSessionState(
    user: UserProfile(id: userId, username: userId, role: 'MEMBER'),
  );
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('异步状态未在预期时间内完成');
}

class _MutableSessionNotifier extends AuthSessionNotifier {
  _MutableSessionNotifier(this.initialState);

  final AuthSessionState initialState;

  @override
  Future<AuthSessionState> build() async => initialState;

  void setSession(AuthSessionState next) {
    state = AsyncData(next);
  }
}

class _MemoryPreferenceSyncService extends PreferenceSyncService {
  _MemoryPreferenceSyncService() : super(api: _NoopUserPreferencesApi());

  final Map<String, Map<String, dynamic>> values =
      <String, Map<String, dynamic>>{};
  int loadCount = 0;

  void put(String userId, String scope, Map<String, dynamic> preferences) {
    values['$userId::$scope'] = Map<String, dynamic>.from(preferences);
  }

  @override
  Future<PreferenceSnapshot> load({
    required String userId,
    required String scope,
  }) async {
    loadCount += 1;
    return PreferenceSnapshot(
      scope: scope,
      preferences: values['$userId::$scope'] ?? const <String, dynamic>{},
      version: values.containsKey('$userId::$scope') ? 0 : null,
    );
  }

  @override
  Future<PreferenceSnapshot> patch({
    required String userId,
    required String scope,
    required Map<String, dynamic> changes,
    Set<String> removeKeys = const <String>{},
  }) async {
    final key = '$userId::$scope';
    final next = Map<String, dynamic>.from(
      values[key] ?? const <String, dynamic>{},
    )..addAll(changes);
    for (final key in removeKeys) {
      next.remove(key);
    }
    values[key] = next;
    return PreferenceSnapshot(scope: scope, preferences: next, version: 0);
  }
}

class _NoopUserPreferencesApi extends UserPreferencesApi {
  _NoopUserPreferencesApi()
    : super(
        ApiClient(
          const AppEnvironment(
            apiBaseUrl: 'http://localhost:8080/api/v1',
            wsBaseUrl: 'ws://localhost:8080/ws',
          ),
        ),
      );
}
