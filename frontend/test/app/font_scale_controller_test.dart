import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/appearance/application/appearance_controller.dart';
import 'package:omninest/app/appearance/application/font_scale_controller.dart';
import 'package:omninest/app/environment.dart';
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

  test('未登录时字体档位从设备偏好恢复', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      appearanceDeviceFontScaleKey: 'comfortable',
    });
    final container = _createContainer(
      session: const AuthSessionState.unauthenticated(),
      bootstrap: const AppBootstrapData(fontScaleName: 'comfortable'),
    );
    addTearDown(container.dispose);

    container.read(fontScaleControllerProvider);
    await container.read(authSessionProvider.future);
    await _waitUntil(
      () =>
          container.read(fontScaleControllerProvider) ==
          FontScalePreset.comfortable,
    );

    expect(
      container.read(fontScaleControllerProvider),
      FontScalePreset.comfortable,
    );
  });

  test('无设备偏好时缺省跟随系统', () async {
    final container = _createContainer(
      session: const AuthSessionState.unauthenticated(),
    );
    addTearDown(container.dispose);

    container.read(fontScaleControllerProvider);
    await container.read(authSessionProvider.future);
    await _waitUntil(
      () =>
          container.read(fontScaleControllerProvider) ==
          FontScalePreset.followSystem,
    );

    expect(
      container.read(fontScaleControllerProvider),
      FontScalePreset.followSystem,
    );
  });

  test('登录后远端 appearance.v1 的 fontScale 覆盖设备值并隔离不同用户', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      appearanceDeviceFontScaleKey: 'compact',
    });
    final syncService =
        _MemoryPreferenceSyncService()
          ..put('user-a', appearancePreferenceScope, <String, dynamic>{
            'themeMode': 'dark',
            'fontScale': 'large',
          })
          ..put('user-b', appearancePreferenceScope, <String, dynamic>{
            'fontScale': 'standard',
          });
    final container = _createContainer(
      session: _session('user-a'),
      bootstrap: const AppBootstrapData(fontScaleName: 'compact'),
      syncService: syncService,
    );
    addTearDown(container.dispose);

    container.read(fontScaleControllerProvider);
    await container.read(authSessionProvider.future);
    await _waitUntil(
      () =>
          container.read(fontScaleControllerProvider) == FontScalePreset.large,
    );

    final sessionNotifier = container.read(authSessionProvider.notifier);
    (sessionNotifier as _MutableSessionNotifier).setSession(_session('user-b'));
    await _waitUntil(
      () =>
          container.read(fontScaleControllerProvider) ==
          FontScalePreset.standard,
    );

    expect(
      container.read(fontScaleControllerProvider),
      FontScalePreset.standard,
    );
  });

  test('远端缺少 fontScale 键时回填当前档位', () async {
    final syncService =
        _MemoryPreferenceSyncService()..put(
          'user-a',
          appearancePreferenceScope,
          <String, dynamic>{'themeMode': 'dark'},
        );
    final container = _createContainer(
      session: _session('user-a'),
      bootstrap: const AppBootstrapData(fontScaleName: 'large'),
      syncService: syncService,
    );
    addTearDown(container.dispose);

    container.read(fontScaleControllerProvider);
    await container.read(authSessionProvider.future);
    await _waitUntil(
      () =>
          syncService
              .values['user-a::$appearancePreferenceScope']?['fontScale'] ==
          'large',
    );

    expect(
      syncService.values['user-a::$appearancePreferenceScope']?['fontScale'],
      'large',
    );
  });

  test('运行时修改档位同步写入设备与当前用户作用域', () async {
    final syncService = _MemoryPreferenceSyncService();
    final container = _createContainer(
      session: _session('user-a'),
      syncService: syncService,
    );
    addTearDown(container.dispose);

    container.read(fontScaleControllerProvider);
    await container.read(authSessionProvider.future);
    await _waitUntil(() => syncService.loadCount >= 1);

    await container
        .read(fontScaleControllerProvider.notifier)
        .setPreset(FontScalePreset.comfortable);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(appearanceDeviceFontScaleKey), 'comfortable');
    expect(
      syncService.values['user-a::$appearancePreferenceScope']?['fontScale'],
      'comfortable',
    );
    expect(
      container.read(fontScaleControllerProvider),
      FontScalePreset.comfortable,
    );
  });

  test('未知档位名回退跟随系统', () {
    expect(FontScalePreset.fromName('huge'), FontScalePreset.followSystem);
    expect(FontScalePreset.fromName(null), FontScalePreset.followSystem);
    expect(FontScalePreset.comfortable.scale, closeTo(1.15, 0.0001));
    expect(FontScalePreset.followSystem.scale, isNull);
  });
}

ProviderContainer _createContainer({
  required AuthSessionState session,
  AppBootstrapData bootstrap = const AppBootstrapData(),
  PreferenceSyncService? syncService,
}) {
  return ProviderContainer.test(
    overrides: [
      appBootstrapDataProvider.overrideWithValue(bootstrap),
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
