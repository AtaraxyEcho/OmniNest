import 'dart:async';

import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/preferences/preference_local_store.dart';
import 'package:omninest/core/preferences/preference_snapshot.dart';
import 'package:omninest/core/preferences/user_preferences_api.dart';

class PreferenceSyncService {
  PreferenceSyncService({
    required UserPreferencesApi api,
    PreferenceLocalStore localStore = const PreferenceLocalStore(),
  }) : _api = api,
       _localStore = localStore;

  static const _versionConflictCode = '7001';

  final UserPreferencesApi _api;
  final PreferenceLocalStore _localStore;
  final Map<String, Future<void>> _tails = {};

  Future<PreferenceSnapshot> load({
    required String userId,
    required String scope,
  }) {
    return _serial(userId, scope, () async {
      final local =
          await _localStore.readSnapshot(userId, scope) ??
          PreferenceSnapshot.empty(scope);
      final pending = await _localStore.readPending(userId, scope);
      final pendingDeletionVersion = await _localStore
          .readPendingDeletionVersion(userId, scope);
      try {
        return await _synchronizeRemote(
          userId: userId,
          scope: scope,
          pending: pending,
          pendingDeletionVersion: pendingDeletionVersion,
        );
      } on Exception {
        return local.copyWith(
          syncState:
              pending == null && pendingDeletionVersion == null
                  ? local.syncState
                  : PreferenceSyncState.pending,
        );
      }
    });
  }

  /// 强制从远端同步偏好，并继续合并本地待提交变更。
  Future<PreferenceSnapshot> synchronize({
    required String userId,
    required String scope,
  }) {
    return _serial(userId, scope, () async {
      final pending = await _localStore.readPending(userId, scope);
      final pendingDeletionVersion = await _localStore
          .readPendingDeletionVersion(userId, scope);
      return _synchronizeRemote(
        userId: userId,
        scope: scope,
        pending: pending,
        pendingDeletionVersion: pendingDeletionVersion,
      );
    });
  }

  Future<PreferenceSnapshot> patch({
    required String userId,
    required String scope,
    required Map<String, dynamic> changes,
    Set<String> removeKeys = const {},
  }) {
    return _serial(userId, scope, () async {
      final current =
          await _localStore.readSnapshot(userId, scope) ??
          PreferenceSnapshot.empty(scope);
      final existingMutation =
          await _localStore.readPending(userId, scope) ??
          const PreferenceMutation(changes: {}, removeKeys: {});
      final mutation = existingMutation.merge(
        nextChanges: changes,
        nextRemoveKeys: removeKeys,
      );
      final optimisticValues = Map<String, dynamic>.from(current.preferences)
        ..addAll(changes);
      for (final key in removeKeys) {
        optimisticValues.remove(key);
      }
      final optimistic = current.copyWith(
        preferences: optimisticValues,
        syncState: PreferenceSyncState.pending,
      );
      await _localStore.writeSnapshot(userId, optimistic);
      await _localStore.writePending(userId, scope, mutation);
      await _localStore.clearPendingDeletion(userId, scope);

      try {
        return await _patchRemote(
          userId: userId,
          scope: scope,
          baseVersion: current.version,
          mutation: mutation,
        );
      } on Exception {
        return optimistic;
      }
    });
  }

  Future<void> delete({required String userId, required String scope}) {
    return _serial(userId, scope, () async {
      final snapshot = await _localStore.readSnapshot(userId, scope);
      if (snapshot?.version == null) {
        await _localStore.writeSnapshot(
          userId,
          PreferenceSnapshot.empty(scope),
        );
        await _localStore.clearPending(userId, scope);
        await _localStore.clearPendingDeletion(userId, scope);
        return;
      }
      final version = snapshot!.version!;
      await _localStore.writePendingDeletionVersion(userId, scope, version);
      await _localStore.writeSnapshot(
        userId,
        PreferenceSnapshot(
          scope: scope,
          preferences: const {},
          version: version,
          syncState: PreferenceSyncState.pending,
        ),
      );
      await _localStore.clearPending(userId, scope);
      try {
        await _deleteRemote(userId: userId, scope: scope, baseVersion: version);
      } on Exception {
        // 删除标记保留到下次加载时重放。
      }
    });
  }

  Future<PreferenceSnapshot> _flushPendingDeletion({
    required String userId,
    required String scope,
    required PreferenceSnapshot remote,
  }) async {
    final version = remote.version;
    if (version == null) {
      return _completeDeletion(userId: userId, scope: scope);
    }
    await _deleteRemote(userId: userId, scope: scope, baseVersion: version);
    return PreferenceSnapshot.empty(scope);
  }

  Future<PreferenceSnapshot> _synchronizeRemote({
    required String userId,
    required String scope,
    required PreferenceMutation? pending,
    required int? pendingDeletionVersion,
  }) async {
    final remote = await _api.getSnapshot(scope);
    if (pendingDeletionVersion != null) {
      return _flushPendingDeletion(
        userId: userId,
        scope: scope,
        remote: remote,
      );
    }
    if (pending == null || pending.isEmpty) {
      await _localStore.writeSnapshot(userId, remote);
      return remote;
    }
    return _flushPending(
      userId: userId,
      scope: scope,
      remote: remote,
      pending: pending,
    );
  }

  Future<void> _deleteRemote({
    required String userId,
    required String scope,
    required int baseVersion,
  }) async {
    try {
      await _api.delete(scope: scope, baseVersion: baseVersion);
    } on AppException catch (error) {
      if (error.code != _versionConflictCode) {
        rethrow;
      }
      final latest = await _api.getSnapshot(scope);
      if (latest.version != null) {
        await _api.delete(scope: scope, baseVersion: latest.version!);
      }
    }
    await _completeDeletion(userId: userId, scope: scope);
  }

  Future<PreferenceSnapshot> _completeDeletion({
    required String userId,
    required String scope,
  }) async {
    final empty = PreferenceSnapshot.empty(scope);
    await _localStore.writeSnapshot(userId, empty);
    await _localStore.clearPending(userId, scope);
    await _localStore.clearPendingDeletion(userId, scope);
    return empty;
  }

  Future<PreferenceSnapshot> _flushPending({
    required String userId,
    required String scope,
    required PreferenceSnapshot remote,
    required PreferenceMutation pending,
  }) {
    return _patchRemote(
      userId: userId,
      scope: scope,
      baseVersion: remote.version,
      mutation: pending,
    );
  }

  Future<PreferenceSnapshot> _patchRemote({
    required String userId,
    required String scope,
    required int? baseVersion,
    required PreferenceMutation mutation,
  }) async {
    var attemptBase = baseVersion;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final saved = await _api.patch(
          scope: scope,
          baseVersion: attemptBase,
          changes: mutation.changes,
          removeKeys: mutation.removeKeys,
        );
        await _localStore.writeSnapshot(userId, saved);
        await _localStore.clearPending(userId, scope);
        return saved;
      } on AppException catch (error) {
        if (error.code != _versionConflictCode) {
          rethrow;
        }
        final latest = await _api.getSnapshot(scope);
        attemptBase = latest.version;
      }
    }
    // 三次冲突后仍失败:抛给上层,保留 pending 供下次同步重放。
    throw const AppException(code: '7001', message: '用户偏好已在其他位置更新，请刷新后重试');
  }

  Future<T> _serial<T>(
    String userId,
    String scope,
    Future<T> Function() action,
  ) async {
    final key = '$userId::$scope';
    final previous = _tails[key] ?? Future<void>.value();
    final completer = Completer<void>();
    _tails[key] = completer.future;
    await previous;
    try {
      return await action();
    } finally {
      completer.complete();
      if (identical(_tails[key], completer.future)) {
        _tails.remove(key);
      }
    }
  }
}
