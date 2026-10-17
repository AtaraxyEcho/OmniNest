import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/preferences/app_bootstrap_data.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

const appearancePreferenceScope = 'appearance.v1';

final appearanceControllerProvider =
    NotifierProvider<AppearanceController, ThemeMode>(AppearanceController.new);

class AppearanceController extends Notifier<ThemeMode> {
  String? _activeUserId;
  int _loadGeneration = 0;

  @override
  ThemeMode build() {
    final initial = themeModeFromName(
      ref.read(appBootstrapDataProvider).themeModeName,
    );
    ref.listen(authSessionProvider, (_, next) {
      final userId = next.value?.user?.id;
      unawaited(_bindUser(userId));
    }, fireImmediately: true);
    return initial;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    await _writeDeviceMode(mode);
    final userId = _activeUserId;
    if (userId == null) {
      return;
    }
    await ref
        .read(preferenceSyncServiceProvider)
        .patch(
          userId: userId,
          scope: appearancePreferenceScope,
          changes: {'schemaVersion': 1, 'themeMode': mode.name},
        );
  }

  /// 从远端重新同步主题偏好，并保留本地待提交变更。
  Future<void> refreshFromRemote() async {
    final userId = _activeUserId;
    if (userId == null) return;
    final snapshot = await ref
        .read(preferenceSyncServiceProvider)
        .synchronize(userId: userId, scope: appearancePreferenceScope);
    if (_activeUserId != userId) return;
    final resolved = themeModeFromName(
      snapshot.preferences['themeMode']?.toString(),
    );
    state = resolved;
    await _writeDeviceMode(resolved);
  }

  Future<void> _bindUser(String? userId) async {
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

    final snapshot = await ref
        .read(preferenceSyncServiceProvider)
        .load(userId: userId, scope: appearancePreferenceScope);
    if (generation != _loadGeneration || _activeUserId != userId) {
      return;
    }
    final remoteName = snapshot.preferences['themeMode']?.toString();
    if (remoteName == null || remoteName.isEmpty) {
      await ref
          .read(preferenceSyncServiceProvider)
          .patch(
            userId: userId,
            scope: appearancePreferenceScope,
            changes: {'schemaVersion': 1, 'themeMode': state.name},
          );
      return;
    }
    final resolved = themeModeFromName(remoteName);
    state = resolved;
    await _writeDeviceMode(resolved);
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
    _ => ThemeMode.system,
  };
}
