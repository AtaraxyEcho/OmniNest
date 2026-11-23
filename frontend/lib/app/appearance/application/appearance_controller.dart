import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/preferences/app_bootstrap_data.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/preferences/preference_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const appearancePreferenceScope = 'appearance.v1';

final appearanceControllerProvider =
    NotifierProvider<AppearanceController, ThemeMode>(AppearanceController.new);

class AppearanceController extends Notifier<ThemeMode> {
  String? _activeUserId;

  /// 上一次绑定的非空账号：用于识别"换号"，避免把上一账号的设备偏好回写到新账号云端。
  String? _lastBoundUserId;
  int _loadGeneration = 0;

  @override
  ThemeMode build() {
    final initial = themeModeFromName(
      ref.read(appBootstrapDataProvider).themeModeName,
    );
    try {
      ref.listen(authSessionProvider, (_, next) {
        final userId = next.value?.user?.id;
        unawaited(_bindUser(userId));
      }, fireImmediately: true);
    } on Object {
      // 测试或离线环境未注入认证会话时静默回退本地偏好。
    }
    return initial;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    await _writeDeviceMode(mode);
    final userId = _activeUserId;
    final service = _tryReadSyncService();
    if (userId == null || service == null) {
      return;
    }
    try {
      await service.patch(
        userId: userId,
        scope: appearancePreferenceScope,
        changes: {'schemaVersion': 1, 'themeMode': mode.name},
      );
    } on Object {
      // 离线或远端不可用时静默保留本地偏好，待下次同步收敛。
    }
  }

  /// 从远端重新同步主题偏好，并保留本地待提交变更。
  Future<void> refreshFromRemote() async {
    final userId = _activeUserId;
    final service = _tryReadSyncService();
    if (userId == null || service == null) return;
    final snapshot = await service.synchronize(
      userId: userId,
      scope: appearancePreferenceScope,
    );
    if (_activeUserId != userId) return;
    final remoteName = snapshot.preferences['themeMode']?.toString();
    if (remoteName == null || remoteName.isEmpty) return;
    final resolved = themeModeFromName(remoteName);
    state = resolved;
    await _writeDeviceMode(resolved);
  }

  Future<void> _bindUser(String? userId) async {
    final previousUserId = _lastBoundUserId;
    _activeUserId = userId;
    final generation = ++_loadGeneration;
    if (userId == null) {
      final preferences = await SharedPreferences.getInstance();
      if (generation == _loadGeneration) {
        state = themeModeFromName(
          preferences.getString(appearanceDeviceModeKey),
        );
      }
      return;
    }

    final service = _tryReadSyncService();
    if (service == null) {
      return;
    }
    try {
      final snapshot = await service.load(
        userId: userId,
        scope: appearancePreferenceScope,
      );
      if (generation != _loadGeneration || _activeUserId != userId) {
        return;
      }
      final remoteName = snapshot.preferences['themeMode']?.toString();
      if (remoteName == null || remoteName.isEmpty) {
        final switchedAccount =
            previousUserId != null && previousUserId != userId;
        _lastBoundUserId = userId;
        if (switchedAccount) {
          // 新账号云端尚无偏好：保留本机呈现即可，禁止把上一账号的选择
          // 反向写成新账号的云端设置。
          return;
        }
        await service.patch(
          userId: userId,
          scope: appearancePreferenceScope,
          changes: {'schemaVersion': 1, 'themeMode': state.name},
        );
        return;
      }
      _lastBoundUserId = userId;
      final resolved = themeModeFromName(remoteName);
      state = resolved;
      await _writeDeviceMode(resolved);
    } on Object {
      // 离线或无同步依赖注入时静默保留本地偏好。
    }
  }

  PreferenceSyncService? _tryReadSyncService() {
    try {
      return ref.read(preferenceSyncServiceProvider);
    } on Object {
      return null;
    }
  }

  Future<void> _writeDeviceMode(ThemeMode mode) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(appearanceDeviceModeKey, mode.name);
    await preferences.remove(legacyGlobalThemeModeKey);
  }
}

ThemeMode themeModeFromName(String? name) {
  return switch (name) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    'system' => ThemeMode.system,
    _ => ThemeMode.dark,
  };
}
