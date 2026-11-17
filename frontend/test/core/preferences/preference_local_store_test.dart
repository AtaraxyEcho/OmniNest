import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/preferences/preference_local_store.dart';
import 'package:omninest/core/preferences/preference_snapshot.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const store = PreferenceLocalStore();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('clearUser 删除该账号的快照与待合并变更，保留其他账号', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('preference.snapshot.user-a.theme', '{"v":1}');
    await preferences.setString('preference.pending.user-a.theme', '{"v":2}');
    await preferences.setInt('preference.pending_delete.user-a.theme', 3);
    await preferences.setString('preference.snapshot.user-b.theme', '{"v":9}');
    await preferences.setString('appearance.theme', 'dark');

    final removed = await store.clearUser('user-a');

    expect(removed, 3);
    expect(preferences.getKeys(), {
      'preference.snapshot.user-b.theme',
      'appearance.theme',
    });
  });

  test('clearUser 对空账号不做任何删除', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('preference.snapshot..theme', '{"v":1}');

    expect(await store.clearUser(''), 0);
    expect(preferences.getKeys(), contains('preference.snapshot..theme'));
  });

  test('登出后重新读取同一账号得到空快照', () async {
    await store.writeSnapshot(
      'user-a',
      const PreferenceSnapshot(
        scope: 'theme',
        version: 4,
        preferences: {'mode': 'dark'},
      ),
    );
    expect(await store.readSnapshot('user-a', 'theme'), isNotNull);

    await store.clearUser('user-a');

    expect(await store.readSnapshot('user-a', 'theme'), isNull);
    expect(await store.readPendingDeletionVersion('user-a', 'theme'), isNull);
  });
}
