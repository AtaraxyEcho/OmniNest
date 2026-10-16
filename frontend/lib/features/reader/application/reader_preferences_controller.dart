import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

const readerPreferenceScope = 'reader';

final readerPreferencesProvider =
    AsyncNotifierProvider<ReaderPreferencesController, Map<String, dynamic>>(
      ReaderPreferencesController.new,
    );

class ReaderPreferencesController extends AsyncNotifier<Map<String, dynamic>> {
  static const _legacyLocalKey = 'reader_view_settings';

  String? _userId;

  /// 远端写入返回后的回写基准。
  ///
  /// 完成回调不得拿 `await` 之前合并的旧图整份发布：那段窗口里发生的其他偏好写入
  /// 会被无声覆盖，表现为连拖两个滑块时后一次设置被前一次回包顶掉。优先取发布时刻
  /// 的实况；仅在状态尚未就绪（首帧读取、错误态）时退回本次合并结果。
  Map<String, dynamic> _liveOr(Map<String, dynamic> captured) =>
      state.asData?.value ?? captured;

  @override
  Future<Map<String, dynamic>> build() async {
    final legacy = await _readLegacyLocal();
    final session = await ref.watch(authSessionProvider.future);
    _userId = session.user?.id;
    final userId = _userId;
    if (userId == null) {
      return legacy;
    }
    final service = ref.read(preferenceSyncServiceProvider);
    var snapshot = await service.load(
      userId: userId,
      scope: readerPreferenceScope,
    );
    if (snapshot.preferences.isEmpty && legacy.isNotEmpty) {
      snapshot = await service.patch(
        userId: userId,
        scope: readerPreferenceScope,
        changes: legacy,
      );
    }
    await _clearLegacyLocal();
    return snapshot.preferences;
  }

  Future<void> save(Map<String, dynamic> preferences) async {
    final merged = <String, dynamic>{...?state.asData?.value, ...preferences};
    state = AsyncData(merged);
    final userId = _userId;
    if (userId == null) {
      return;
    }
    final snapshot = await ref
        .read(preferenceSyncServiceProvider)
        .patch(
          userId: userId,
          scope: readerPreferenceScope,
          changes: preferences,
        );
    state = AsyncData({..._liveOr(merged), ...snapshot.preferences});
  }

  /// 从远端重新同步阅读偏好，并保留本地待提交变更。
  Future<void> refreshFromRemote() async {
    final userId = _userId;
    if (userId == null) return;
    final snapshot = await ref
        .read(preferenceSyncServiceProvider)
        .synchronize(userId: userId, scope: readerPreferenceScope);
    if (_userId != userId) return;
    state = AsyncData(snapshot.preferences);
  }

  Future<Map<String, dynamic>> _readLegacyLocal() async {
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

  Future<void> _clearLegacyLocal() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_legacyLocalKey);
  }
}
