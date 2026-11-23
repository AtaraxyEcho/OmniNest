import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/preferences/preference_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const readerPreferenceScope = 'reader';

final readerPreferencesProvider =
    AsyncNotifierProvider<ReaderPreferencesController, Map<String, dynamic>>(
      ReaderPreferencesController.new,
    );

class ReaderPreferencesController extends AsyncNotifier<Map<String, dynamic>> {
  static const _legacyLocalKey = 'reader_view_settings';
  static const _syncDebounce = Duration(milliseconds: 250);

  String? _userId;
  Timer? _syncDebounceTimer;
  final Map<String, dynamic> _pendingRemoteChanges = <String, dynamic>{};

  /// 远端写入返回后的回写基准。
  ///
  /// 完成回调不得拿 `await` 之前合并的旧图整份发布：那段窗口里发生的其他偏好写入
  /// 会被无声覆盖，表现为连拖两个滑块时后一次设置被前一次回包顶掉。优先取发布时刻
  /// 的实况；仅在状态尚未就绪（首帧读取、错误态）时退回本次合并结果。
  Map<String, dynamic> _liveOr(Map<String, dynamic> captured) =>
      state.asData?.value ?? captured;

  @override
  Future<Map<String, dynamic>> build() async {
    ref.onDispose(() {
      _syncDebounceTimer?.cancel();
      _syncDebounceTimer = null;
      _pendingRemoteChanges.clear();
    });
    Future<AuthSessionState>? sessionFuture;
    try {
      sessionFuture = ref.watch(authSessionProvider.future);
    } on Object {
      sessionFuture = null;
    }
    final local = await _readLocal();
    if (sessionFuture == null) {
      _userId = null;
      return local;
    }
    AuthSessionState session;
    try {
      session = await sessionFuture;
    } on Object {
      _userId = null;
      return local;
    }
    _userId = session.user?.id;
    final userId = _userId;
    if (userId == null) {
      return local;
    }
    final service = _tryReadSyncService();
    if (service == null) {
      return local;
    }
    try {
      var snapshot = await service.load(
        userId: userId,
        scope: readerPreferenceScope,
      );
      if (snapshot.preferences.isEmpty && local.isNotEmpty) {
        snapshot = await service.patch(
          userId: userId,
          scope: readerPreferenceScope,
          changes: local,
        );
      }
      final resolved =
          snapshot.preferences.isEmpty ? local : snapshot.preferences;
      if (resolved.isNotEmpty) {
        await _writeLocal(resolved);
      }
      return resolved;
    } on Object {
      return local;
    }
  }

  Future<void> save(Map<String, dynamic> preferences) async {
    final merged = <String, dynamic>{...?state.asData?.value, ...preferences};
    state = AsyncData(merged);
    await _writeLocal(merged);
    final userId = _userId;
    if (userId == null) {
      return;
    }
    _pendingRemoteChanges.addAll(preferences);
    _syncDebounceTimer?.cancel();
    _syncDebounceTimer = Timer(_syncDebounce, () {
      unawaited(_flushRemotePatch(userId, merged));
    });
  }

  /// 从远端重新同步阅读偏好，并保留本地待提交变更。
  Future<void> refreshFromRemote() async {
    final userId = _userId;
    final service = _tryReadSyncService();
    if (userId == null || service == null) return;
    final snapshot = await service.synchronize(
      userId: userId,
      scope: readerPreferenceScope,
    );
    if (_userId != userId) return;
    state = AsyncData(snapshot.preferences);
    await _writeLocal(snapshot.preferences);
  }

  Future<void> _flushRemotePatch(
    String userId,
    Map<String, dynamic> fallbackMerged,
  ) async {
    if (_userId != userId || _pendingRemoteChanges.isEmpty) {
      return;
    }
    final service = _tryReadSyncService();
    if (service == null) {
      _pendingRemoteChanges.clear();
      return;
    }
    final payload = Map<String, dynamic>.from(_pendingRemoteChanges);
    _pendingRemoteChanges.clear();
    try {
      final snapshot = await service.patch(
        userId: userId,
        scope: readerPreferenceScope,
        changes: payload,
      );
      if (_userId != userId) return;
      final merged = <String, dynamic>{
        ..._liveOr(fallbackMerged),
        ...snapshot.preferences,
      };
      state = AsyncData(merged);
      await _writeLocal(merged);
    } on Object {
      // 离线或远端不可用时静默保留本地偏好，由 pending 与下次同步收敛。
    }
  }

  PreferenceSyncService? _tryReadSyncService() {
    try {
      return ref.read(preferenceSyncServiceProvider);
    } on Object {
      return null;
    }
  }

  Future<Map<String, dynamic>> _readLocal() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_legacyLocalKey);
    if (raw == null || raw.isEmpty) {
      return const {};
    }
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } on FormatException {
      return const {};
    }
  }

  Future<void> _writeLocal(Map<String, dynamic> preferences) async {
    final store = await SharedPreferences.getInstance();
    await store.setString(_legacyLocalKey, jsonEncode(preferences));
  }
}
