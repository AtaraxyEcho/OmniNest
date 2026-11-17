import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/core/preferences/preference_snapshot.dart';
import 'package:omninest/core/preferences/preference_sync_service.dart';
import 'package:omninest/core/preferences/user_preferences_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('offline patch is restored and flushed for the same user', () async {
    final api = _FakePreferencesApi()..offline = true;
    final service = PreferenceSyncService(api: api);

    final optimistic = await service.patch(
      userId: 'user-a',
      scope: 'appearance.v1',
      changes: {'themeMode': 'dark'},
    );

    expect(optimistic.syncState, PreferenceSyncState.pending);
    api.offline = false;
    final synced = await service.load(userId: 'user-a', scope: 'appearance.v1');
    expect(synced.syncState, PreferenceSyncState.synced);
    expect(synced.preferences['themeMode'], 'dark');
  });

  test('pending mutations are isolated by user id', () async {
    final api = _FakePreferencesApi()..offline = true;
    final service = PreferenceSyncService(api: api);

    await service.patch(
      userId: 'user-a',
      scope: 'locale.v1',
      changes: {'language': 'en'},
    );

    final otherUser = await service.load(userId: 'user-b', scope: 'locale.v1');
    expect(otherUser.preferences, isEmpty);
  });

  test(
    'strict synchronize reports remote failure instead of acknowledging it',
    () async {
      final api = _FakePreferencesApi()..offline = true;
      final service = PreferenceSyncService(api: api);

      await expectLater(
        service.synchronize(userId: 'user-a', scope: 'appearance.v1'),
        throwsA(isA<AppException>()),
      );
    },
  );

  test(
    'strict synchronize flushes local pending mutation over remote values',
    () async {
      final api =
          _FakePreferencesApi()
            ..remote['appearance.v1'] = const PreferenceSnapshot(
              scope: 'appearance.v1',
              preferences: {'themeMode': 'light', 'contrast': 'normal'},
              version: 3,
            )
            ..offline = true;
      final service = PreferenceSyncService(api: api);
      await service.patch(
        userId: 'user-a',
        scope: 'appearance.v1',
        changes: {'themeMode': 'dark'},
      );

      api.offline = false;
      final synchronized = await service.synchronize(
        userId: 'user-a',
        scope: 'appearance.v1',
      );

      expect(synchronized.preferences, {
        'themeMode': 'dark',
        'contrast': 'normal',
      });
    },
  );

  test(
    'version conflict refreshes and retries local dirty fields once',
    () async {
      final api =
          _FakePreferencesApi()
            ..remote['appearance.v1'] = const PreferenceSnapshot(
              scope: 'appearance.v1',
              preferences: {'themeMode': 'light', 'other': true},
              version: 5,
            )
            ..conflictNextPatch = true;
      final service = PreferenceSyncService(api: api);

      final result = await service.patch(
        userId: 'user-a',
        scope: 'appearance.v1',
        changes: {'themeMode': 'dark'},
      );

      expect(api.patchCount, 2);
      expect(result.preferences, {'themeMode': 'dark', 'other': true});
    },
  );

  test('offline delete is restored and flushed for the same user', () async {
    final api =
        _FakePreferencesApi()
          ..remote['music.visual.v1'] = const PreferenceSnapshot(
            scope: 'music.visual.v1',
            preferences: {'enabled': true},
            version: 4,
          );
    final service = PreferenceSyncService(api: api);

    await service.load(userId: 'user-a', scope: 'music.visual.v1');
    api.offline = true;
    await service.delete(userId: 'user-a', scope: 'music.visual.v1');

    final offline = await service.load(
      userId: 'user-a',
      scope: 'music.visual.v1',
    );
    expect(offline.preferences, isEmpty);
    expect(offline.syncState, PreferenceSyncState.pending);

    api.offline = false;
    final synced = await service.load(
      userId: 'user-a',
      scope: 'music.visual.v1',
    );
    expect(synced.preferences, isEmpty);
    expect(synced.syncState, PreferenceSyncState.synced);
    expect(api.remote.containsKey('music.visual.v1'), isFalse);
    expect(api.deleteCount, 2);
  });

  test('delete version conflict refreshes and retries once', () async {
    final api =
        _FakePreferencesApi()
          ..remote['appearance.v1'] = const PreferenceSnapshot(
            scope: 'appearance.v1',
            preferences: {'themeMode': 'dark'},
            version: 5,
          );
    final service = PreferenceSyncService(api: api);

    await service.load(userId: 'user-a', scope: 'appearance.v1');
    api.remote['appearance.v1'] = const PreferenceSnapshot(
      scope: 'appearance.v1',
      preferences: {'themeMode': 'light'},
      version: 6,
    );
    api.conflictNextDelete = true;
    await service.delete(userId: 'user-a', scope: 'appearance.v1');

    expect(api.deleteCount, 2);
    expect(api.remote.containsKey('appearance.v1'), isFalse);
  });

  test('pending deletions are isolated by user id', () async {
    final api =
        _FakePreferencesApi()
          ..remote['locale.v1'] = const PreferenceSnapshot(
            scope: 'locale.v1',
            preferences: {'language': 'zh'},
            version: 2,
          );
    final service = PreferenceSyncService(api: api);

    await service.load(userId: 'user-a', scope: 'locale.v1');
    api.offline = true;
    await service.delete(userId: 'user-a', scope: 'locale.v1');

    final otherUser = await service.load(userId: 'user-b', scope: 'locale.v1');
    expect(otherUser.preferences, isEmpty);
    expect(otherUser.syncState, PreferenceSyncState.synced);
  });
}

class _FakePreferencesApi extends UserPreferencesApi {
  _FakePreferencesApi()
    : super(
        ApiClient(
          const AppEnvironment(
            apiBaseUrl: 'http://localhost:8080/api/v1',
            wsBaseUrl: 'ws://localhost:8080/ws',
          ),
        ),
      );

  final Map<String, PreferenceSnapshot> remote = {};
  bool offline = false;
  bool conflictNextPatch = false;
  bool conflictNextDelete = false;
  int patchCount = 0;
  int deleteCount = 0;

  @override
  Future<PreferenceSnapshot> getSnapshot(String scope) async {
    if (offline) {
      throw const AppException(code: 'OFFLINE', message: 'offline');
    }
    return remote[scope] ?? PreferenceSnapshot.empty(scope);
  }

  @override
  Future<PreferenceSnapshot> patch({
    required String scope,
    required int? baseVersion,
    required Map<String, dynamic> changes,
    Set<String> removeKeys = const {},
  }) async {
    patchCount += 1;
    if (offline) {
      throw const AppException(code: 'OFFLINE', message: 'offline');
    }
    if (conflictNextPatch) {
      conflictNextPatch = false;
      throw const AppException(code: '7001', message: 'conflict');
    }
    final current = remote[scope] ?? PreferenceSnapshot.empty(scope);
    final values = Map<String, dynamic>.from(current.preferences)
      ..addAll(changes);
    for (final key in removeKeys) {
      values.remove(key);
    }
    final saved = PreferenceSnapshot(
      scope: scope,
      preferences: values,
      version: (current.version ?? -1) + 1,
    );
    remote[scope] = saved;
    return saved;
  }

  @override
  Future<void> delete({required String scope, required int baseVersion}) async {
    deleteCount += 1;
    if (offline) {
      throw const AppException(code: 'OFFLINE', message: 'offline');
    }
    if (conflictNextDelete) {
      conflictNextDelete = false;
      throw const AppException(code: '7001', message: 'conflict');
    }
    final current = remote[scope];
    if (current != null && current.version != baseVersion) {
      throw const AppException(code: '7001', message: 'conflict');
    }
    remote.remove(scope);
  }
}
