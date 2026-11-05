import 'dart:convert';

import 'package:omninest/core/preferences/preference_snapshot.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PreferenceLocalStore {
  const PreferenceLocalStore();

  Future<PreferenceSnapshot?> readSnapshot(String userId, String scope) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_snapshotKey(userId, scope));
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic>
          ? PreferenceSnapshot.fromJson(decoded)
          : null;
    } on FormatException {
      await preferences.remove(_snapshotKey(userId, scope));
      return null;
    }
  }

  Future<void> writeSnapshot(String userId, PreferenceSnapshot snapshot) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _snapshotKey(userId, snapshot.scope),
      jsonEncode(snapshot.toJson()),
    );
  }

  Future<PreferenceMutation?> readPending(String userId, String scope) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_pendingKey(userId, scope));
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic>
          ? PreferenceMutation.fromJson(decoded)
          : null;
    } on FormatException {
      await preferences.remove(_pendingKey(userId, scope));
      return null;
    }
  }

  Future<void> writePending(
    String userId,
    String scope,
    PreferenceMutation mutation,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    if (mutation.isEmpty) {
      await preferences.remove(_pendingKey(userId, scope));
      return;
    }
    await preferences.setString(
      _pendingKey(userId, scope),
      jsonEncode(mutation.toJson()),
    );
  }

  Future<void> clearPending(String userId, String scope) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_pendingKey(userId, scope));
  }

  Future<int?> readPendingDeletionVersion(String userId, String scope) async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getInt(_pendingDeletionKey(userId, scope));
  }

  Future<void> writePendingDeletionVersion(
    String userId,
    String scope,
    int version,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_pendingDeletionKey(userId, scope), version);
  }

  Future<void> clearPendingDeletion(String userId, String scope) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_pendingDeletionKey(userId, scope));
  }

  /// 登出时删除该账号的全部偏好快照与待合并变更。
  ///
  /// 键名带账号不会跨账号泄露，但登出后仍长期留在设备上：天气城市、界面偏好
  /// 这类内容属于账号隐私，且下次登录会以"本地已有快照"的身份参与合并。
  /// 三个键族必须一起清，只清快照会让待合并变更在下次登录时被重新写回。
  Future<int> clearUser(String userId) async {
    if (userId.isEmpty) {
      return 0;
    }
    final preferences = await SharedPreferences.getInstance();
    final prefixes = <String>[
      'preference.snapshot.$userId.',
      'preference.pending.$userId.',
      'preference.pending_delete.$userId.',
    ];
    final targets = preferences
        .getKeys()
        .where((key) => prefixes.any(key.startsWith))
        .toList(growable: false);
    for (final key in targets) {
      await preferences.remove(key);
    }
    return targets.length;
  }

  String _snapshotKey(String userId, String scope) {
    return 'preference.snapshot.$userId.$scope';
  }

  String _pendingKey(String userId, String scope) {
    return 'preference.pending.$userId.$scope';
  }

  String _pendingDeletionKey(String userId, String scope) {
    return 'preference.pending_delete.$userId.$scope';
  }
}
